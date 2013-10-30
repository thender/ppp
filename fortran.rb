$: << (basedir=File.dirname($0)) << File.join(basedir,"lib")

require "ostruct"
require "yaml"

require "treetop/runtime"
require "common"

module Fortran

  include Common

  def add_branch_target(label)
    branch_targets=(env[:branch_targets]||={})
    label_array=(branch_targets["#{label}"]||=[])
    label_array.push(label)
  end

  def env
    @envstack.last
  end

  def envpop(scope_change=true)
    oldenv=@envstack.pop
    @envstack.push({}) if @envstack.empty?
    env[:global]=oldenv[:global]
    unless scope_change
      env_scope_items.each { |k| env[k]=oldenv[k] }
    end
    oldenv
  end

  def envpush(scope_change=true)
    keep={}
    keep[:global]=env.delete(:global)
    env_scope_items.each do |k|
      if (v=env.delete(k))
        keep[k]=v unless scope_change
      end
    end
    @envstack.push(deepcopy(env))
    keep.each { |k,v| env[k]=v }
    @redefs={}
    nil
  end

  def env_scope_items
    [
      :assign_map,
      :assigned_goto_targets,
      :branch_targets
    ]
  end

  def modenv(m)
    @modenv_cache||={}
    return @modenv_cache[m] if @modenv_cache.has_key?(m)
    if d=@incdirs.find_all { |x| File.exist?(envfile(m,x)) }[0]
      f=envfile(m,d)
      begin
        return @modenv_cache[m]=YAML.load(File.open(f))
      rescue Exception=>ex
        s="ERROR: #{ex.message}\n"
        s+=ex.backtrace.reduce(s) { |m,x| m+="#{x}\n" }
        s+="Error reading #{f}"
        fail s
      end
    end
    {}
  end

  def redef(var)
    var="#{var}" unless var.is_a?(String)
    if defined?(@redefs)
      unless @redefs[var]
        env.delete(var)
        @redefs[var]=true
      end
    end
  end

  def sp_access_stmt(access_spec,access_stmt_option)
    if access_stmt_option.is_a?(Access_Stmt_Option)
      names=access_stmt_option.names
    else
      names=[]
    end
    names.each { |x| redef(x) }
    if access_spec.private?
      p="private"
    elsif access_spec.public?
      p="public"
    else
      p="_default"
    end
    if access_stmt_option.is_a?(Access_Stmt_Option)
      access_stmt_option.names.each { |x| varsetattr(x,"access",p) }
    else
      @access=p
      env.each do |n,h|
        varsetattr(n,"access",p) if vargetattr(n,"access")=="_default"
      end
    end
    true
  end

  def sp_allocatable_stmt(array_names_and_deferred_shape_spec_lists)
    a=array_names_and_deferred_shape_spec_lists
    env[:allocatable]||=[]
    a.names.each do |var|
      redef(var)
      # Record that this var has been marked allocatable, which means that it
      # must be an array with deferred bounds.
      env[:allocatable].push(var)
      varsetattr(var,"sort","_array")
      # Correct for the case where this array has already been seen and its
      # bounds incorrectly marked as assumed.
      env[var].keys.each { |k| env[var][k]="_deferred" if k=~/[lu]b\d+/ }
    end
    # In case this array has not previously been seen, record its array specs.
    a.items.each do |x|
      if x.array_spec
        env[x.name].merge!(array_attrs(x.array_spec,{},@distribute))
      end
    end
    true
  end

  def sp_alt_return_spec(label)
    add_branch_target(label)
  end

  def sp_assign_stmt(label,scalar_int_variable)
    assign_map=(env[:assign_map]||={})
    var_array=(assign_map["#{label}"]||=Set.new)
    var_array.add("#{scalar_int_variable}")
    true
  end

  def sp_assigned_goto_stmt(scalar_int_variable)
    assigned_goto_targets=(env[:assigned_goto_targets]||={})
    var_array=(assigned_goto_targets["#{scalar_int_variable}"]||=[])
    var_array.push(scalar_int_variable)
    true
  end

  def sp_arithmetic_if_stmt(label1,label2,label3)
    [label1,label2,label3].each { |x| add_branch_target(x) }
    true
  end

  def sp_block_data
    envpop
    true
  end

  def sp_block_data_stmt
    envpush
    true
  end

  def sp_default_char_variable?(var)
    if var.is_a?(Name)
      # fine as-is
    elsif var.is_a?(Data_Ref)
      var=var.rightmost.name
    else
      fail "ERROR: Unexpected node type"
    end
    varenv=env["#{var}"]
    if varenv and varenv["type"]=="character" and varenv["kind"]=="_default"
      true
    else
      nil
    end
  end

  def sp_dimension_stmt(array_names_and_specs)
    array_names_and_specs.e.each do |x|
      if x.is_a?(Array_Name_And_Spec)
        var=x.name
        redef(var)
        array_spec=x.spec.e[0]
        env[var]||={}
        env[var].merge!(array_attrs(array_spec,{},@distribute))
      end
    end
    array_names_and_specs.names.each { |x| varsetattr(x,"sort","_array") }
    true
  end

  def sp_dolabel_pop
    # F90:R817 block-do-construct's do-stmt always pushes a label: either the
    # actual label (when do-stmt is a label-do-stmt), or the symbol :nolabel
    # (when do-stmt is a nonlabel-do-stmt). F90:R826 nonblock-do-construct
    # requires label-do-stmt components, each of whose labels will be pushed
    # onto the label stack. But these labels may be repeated, to match a single
    # do-term-shared-stmt.
    @dolabels.pop
    true
  end

  def sp_dolabel_push(label)
    # A non-label-do-stmt pushes the symbol :nolabel onto the stack, which must
    # not be converted to a string, to avoid matching a potential literal label
    # 'nolabel'. If the passed-in label is not a symbol, push its string version
    # onto the label stack.
    @dolabels.push((label.is_a?(Symbol))?(label):("#{label}"))
    true
  end

  def sp_dolabel_repeat?
    # Report whether the top two labels on the label stack match. Some grammar
    # rules only match when this is not the case; others require it. But if the
    # topmost label is the symbol :nolabel, never consider that a repeat, as
    # nonlabel versions of block-do-construct may have arbitrarily deep nesting.
    return false if @dolabels.last==:nolabel
    "#{@dolabels[-1]}"=="#{@dolabels[-2]}"
  end

  def sp_env_pullup(node)
    if node.e[0].respond_to?(:envref) and (x=node.e[0].envref)
      node.envref=x
    end
    true
  end

  def sp_function_stmt(function_name,dummy_arg_name_list,result_option)
    envpush
    (env["#{function_name}"]||={})["function"]=true
    if result_option.is_a?(Result_Option)
      env[:result]="#{result_option.name}"
    end
    if dummy_arg_name_list.is_a?(Dummy_Arg_Name_List)
      first="#{dummy_arg_name_list.e[0]}"
      rest=dummy_arg_name_list.e[1].e
      env[:args]=rest.reduce([first]) { |m,x| m.push("#{x.e[1]}") }
    end
    true
  end

  def sp_function_subprogram(function_stmt)
    var="#{function_stmt.name}"
    varenv=(env[var]||={})
    varenv["sort"]||="_scalar"
    access=varenv["access"]||@access
    if (type_spec=function_stmt.type_spec)
      varenv["kind"]="#{type_spec.kind}"
      varenv["type"]="#{type_spec.type}"
    elsif (result=env[:result])
      varenv.merge!(env["#{result}"])
    end
    varenv["access"]=access
    envpop
    true
  end

  def sp_goto_stmt(label)
    add_branch_target(label)
    true
  end

  def sp_hollerith_check_count
    @hollerith_count+=1
    (@hollerith_count>@hollerith_size)?(false):(true)
  end

  def sp_hollerith_reset_count
    @hollerith_count=0
    true
  end

  def sp_hollerith_set_length(digit_string)
    @hollerith_size=Integer("#{digit_string}")
    true
  end

  def sp_intent_stmt(dummy_arg_name_list)
    dummy_arg_name_list.names.each { |x| redef(x) }
    true
  end

  def sp_interface_body
    envpop
    true
  end

  def sp_io_spec_end(label)
    add_branch_target(label)
    true
  end

  def sp_io_spec_eor(label)
    add_branch_target(label)
    true
  end

  def sp_io_spec_err(label)
    add_branch_target(label)
    true
  end

  def sp_is_array?(node)
    return false unless node.respond_to?(:name)
    vargetattr(node.name,"sort")=="_array"
  end

  def sp_label(label)
    n=label.e.reduce("") { |m,x| m+"#{x}" }.to_i
    (env[:global][:labels]||=Set.new).add(n)
    true
  end

  def sp_label_list(first,rest)
    add_branch_target(first)
    rest.e.each { |x| add_branch_target(x.label) }
  end

  def sp_main_program
    envpop
    true
  end

  def sp_module(module_stmt,module_subprogram_part)
    if module_subprogram_part.is_a?(Module_Subprogram_Part)
      fn_env=module_subprogram_part.subprograms.reduce({}) do |m,x|
        m.merge(x.env.select { |k,v| x=="#{x.name}" and v["function"] })
      end
      env.merge!(fn_env)
    end
    # The environment has already been modified by processing the module's
    # specification-part, part, so always write out the module file.
    write_envfile(module_stmt.name,env)
    envpop
    @access="_default"
    true
  end

  def sp_module_stmt
    envpush
    true
  end

  def sp_namelist_group_name?(name)
    return false unless (varenv=env["#{name}"])
    varenv["sort"]=="_namelist"
  end

  def sp_namelist_stmt(first,rest)
    rest.sets.push(first).each do |set|
      name="#{set.name}"
      redef(name)
      env[name]||={}
      env[name]["sort"]="_namelist"
      env[name]["objects"]||=[]
      env[name]["access"]||=@access
      set.objects.each { |object| env[name]["objects"].push("#{object}") }
    end
    true
  end

  def sp_nonblock_do_end?(node)
    # F90:R826 requires that the label on the terminating action-stmt match that
    # of the matching label-do-stmt. If this isn't the case, this node cannot be
    # the end of a nonblock-do-construct.
    return false unless node.respond_to?(:label)
    return false if "#{node.label}".empty?
    ("#{node.label}"==@dolabels.last)?(true):(false)
  end

  def sp_optional_stmt(dummy_arg_name_list)
    dummy_arg_name_list.names.each { |x| redef(x) }
    true
  end

  def sp_parameter_stmt(named_constant_def_list)
    named_constant_def_list.names.each do |x|
      redef(x)
      varsetattr(x,"parameter","_true")
    end
    true
  end

  def sp_pointer_stmt(object_names_and_spec_lists)
    object_names_and_spec_lists.names.each { |x| redef x }
    true
  end

  def sp_program_stmt
    envpush
    true
  end

  def sp_save_stmt(save_stmt_entity_list)
    if save_stmt_entity_list.is_a?(Save_Stmt_Entity_List)
      save_stmt_entity_list.names.each { |x| redef x }
    end
    true
  end

  def sp_subroutine_stmt(dummy_arg_list_option)
    envpush
    if dummy_arg_list_option.e
      if dummy_arg_list_option.e[1].is_a?(Dummy_Arg_List)
        dummy_arg_list=dummy_arg_list_option.e[1]
        first="#{dummy_arg_list.e[0]}"
        rest=dummy_arg_list.e[1].e
        env[:args]=rest.reduce([first]) { |m,x| m.push("#{x.e[1]}") }
      end
    end
    true
  end

  def sp_subroutine_subprogram
    envpop
    true
  end

  def sp_target_stmt(target_object_list)
    target_object_list.objects.each do |x|
      unless x.is_a?(Array_Name_And_Spec) or x.is_a?(Variable_Name)
        fail "ERROR: Unexpected node type"
      end
      var=x.name
      varsetattr(var,"sort","_array") if x.is_a?(Array_Name_And_Spec)
      redef(var)
    end
    true
  end

  def sp_type_declaration_stmt(type_spec,attr_spec_option,entity_decl_list)
    entity_decl_list.names.each { |x| redef(x) unless (varenv=env["#{x}"]) and varenv["function"] }
    varattrs=entity_decl_list.varattrs(@distribute)
    if x=attrchk(attr_spec_option,:dimension?)
      array_spec=x.e[0]
      varattrs.each do |v,p|
        p["sort"]="_array"
        array_attrs(array_spec,p,@distribute)
      end
    end
    if attrchk(attr_spec_option,:allocatable?)
      varattrs.each { |v,p| p["allocatable"]="_true" }
    end
    if attrchk(attr_spec_option,:parameter?)
      varattrs.each { |v,p| p["parameter"]="_true" }
    end
    if attrchk(attr_spec_option,:private?)
      varattrs.each { |v,p| p["access"]="private" }
    elsif attrchk(attr_spec_option,:public?)
      varattrs.each { |v,p| p["access"]="public" }
    else
      varattrs.each { |v,p| p["access"]=@access }
    end
    varattrs.each do |v,p|
      name="#{v}"
      varenv=(env[name]||={})
      ["access","sort"].each { |x| p.delete(x) if varenv.include?(x) }
      p["type"]=type_spec.type
      p["kind"]=type_spec.kind
      if env[:allocatable] and env[:allocatable].include?(name)
        p.keys.each { |k| p[k]="_deferred" if k=~/[lu]b\d+/ }
        p["allocatable"]="_true"
      end
      varenv.merge!(p)
    end
    true
  end

  def sp_use_stmt(modulename,list)
    def use_add(modulename,usenames,localnames)
      env[:uses]||={}
      names=localnames.zip(usenames)
      unless env[:uses][modulename]
        env[:uses][modulename]=names
      else
        unless uses?(modulename,:all)
          names.each do |x|
            env[:uses][modulename].push(x) unless uses?(modulename,x)
          end
        end
      end
    end
    m="#{modulename}"
    if list.respond_to?(:usenames)
      use_add(m,list.usenames,list.localnames)
    else
      env[:uses]||={}
      env[:uses][m]=[[:all]]
    end
    modenv(m).each do |x|
      varname=x[0]
      varattr=x[1]
      localname=use_localname(m,varname)
      if uses?(m,:all) or uses?(m,localname)
        varattr["access"]=(e=env[varname] and a=e["access"])?(a):(@access)
        env[localname]=varattr
      end
    end
    true
  end

  def use_localname(modulename,usename)
    if i=use_usenames(modulename).index(usename)
      return use_localnames(modulename)[i]
    end
    return usename
  end

  def use_usenames(modulename)
    e=(is_a?(T))?(use_part.env):(env)
    return [] unless e[:uses]
    e[:uses][modulename].map { |x| x[1] }
  end

  def vargetattr(n,k)
    return nil unless env["#{n}"]
    env["#{n}"]["#{k}"]||nil
  end

  def varsetattr(n,k,v)
    env["#{n}"]||={}
    env["#{n}"]["#{k}"]=v
  end

  # Extension of SyntaxNode class

  class Treetop::Runtime::SyntaxNode

    def to_s
      ""
    end

    def transform_common(method)
      transform_children(method)
      send(method) if respond_to?(method)
    end

    def transform_children(method)
      e.each { |x| x.transform_common(method) if x } if e
      self
    end

    def transform_top(method)
      transform_common(method)
      self
    end

    alias e elements

  end

  # Generic subclasses

  class T < Treetop::Runtime::SyntaxNode

    include Common

    attr_accessor :envref,:srcfile

    def initialize(*args)
      super(*args)
      @envref=input.envstack.last
      @srcfile=nil
    end

    def ancestor(*classes)
      n=parent
      begin
        return n if classes.any? { |x| n.is_a?(x) }
      end while n=n.parent
      nil
    end

    def block_left
      s=env[:global]
      s[:level]||=0
      s[:level]-=1 if s[:level]>0
    end

    def block_right
      s=env[:global]
      s[:level]||=0
      s[:level]+=1
    end

		def cat_stmt
			stmt(e[1..-2].map { |x| "#{x}" }.join)
		end
    
    def declaration_constructs
      specification_part.e[2]
    end

    def declare(type,name,props={})
      # Override in *_fortran.rb, restrictions on allowable definitions may
      # differ between applications. It may be acceptable to simply disregard
      # a request to define an already-defined variable, in which case a single
      # method suitable for all applications could be defined here.
      fail "ERROR: Fortran#declare not implemented"
    end

    def env
      envref
    end

    def execution_part
      scoping_unit.e[2]
    end

    def ik(e,c,a)
      # identity keep: If the [e]lement's string form equals the [c]ontrol
      # string, return the element itself; otherwise return the [a]lternate.
      ("#{e}"==c)?(e):(a)
    end

    def indent(s)
      (s.empty?)?(s):((" "*2*level)+s)
    end

    def ir(e,c,a)
      # identity replace: If the [e]lement's string form equals the [c]ontrol
      # string, return the [a]lternate; otherwise return the element itself.
      ("#{e}"==c)?(a):(e)
    end

    def inside?(*class_or_classes)
      (ancestor(*class_or_classes))?(true):(false)
    end

    def label_create
      labels=(env[:global][:labels]||=Set.new)
      99999.downto(1).each do |n|
        unless labels.include?(n)
          labels.add(n)
          return n
        end
      end
      fail "ERROR: No unused labels available"
    end

    def label_delete
      return nil if (l=label).empty?
      e[0]=Treetop::Runtime::SyntaxNode.new("",nil)
      l
    end

    def level
      env[:global][:level]||=0
    end

    def list_str
      s="#{e[0]}"
      s=e[1].e.reduce(s) { |m,x| m+"#{x.e[0]}#{x.e[1]}" } if e[1].e
      s
    end

    def raw(code,rule,srcfile,opts={})
      opts[:product]=:raw_tree
      Translator.new.process(code,rule,srcfile,opts)
    end

    def replace_element(code,rule,node=self)
      tree=raw(code,rule,@srcfile,{:nl=>false,:env=>node.env})
      node=node.parent while "#{node}"=="#{node.parent}"
      tree.parent=node.parent
      block=node.parent.e
      block[block.index(node)]=tree
    end

    def replace_statement(code)
      code=code.join("\n") if code.is_a?(Array)
      tree=raw(code,:block,@srcfile,{:env=>self.env})
      tree.parent=self.parent
      block=self.parent.e
      block[block.index(self)]=tree
    end

    def sa(e)
      # space after: If the [e]lement's string form is empty, return that; else
      # return its string form with a trailing space appended.
      ("#{e}"=="")?(""):("#{e} ")
    end

    def sb(e)
      # space before: If the [e]lement's string form is empty, return that; else
      # return its string form with a prepended space.
      ("#{e}"=="")?(""):(" #{e}")
    end

    def scoping_unit
      ancestor(Scoping_Unit)
    end

    def space(all=false)
      a=(all)?(e):(e[1..-1])
      a.map { |x| "#{x}" }.join(" ").strip
    end

    def specification_part
      ((is_a?(Scoping_Unit))?(self):(scoping_unit)).e[1]
    end

    def stmt(s)
      "#{sa(e[0])}#{s}\n"
    end

    def str0
      text_value
    end

    def str1
      strmemo
    end

    def strmemo
      @strmemo_||(@strmemo_=str0)
    end

    def to_s
      ($INDENTED)?(str1):(str0)
    end

    def use(modname,usenames=[])
      unless uses?(modname,:all)
        new_usenames=[]
        code="use #{modname}"
        unless usenames.empty?
          list=[]
          usenames.each do |x|
            h=x.is_a?(Hash)
            localname=(h)?(x.keys.first):(nil)
            usename=(h)?(x.values.first):(x)
            unless uses?(modname,usename)
              list.push(((h)?("#{localname}=>#{usename}"):("#{usename}")))
              new_usenames.push([localname||usename,usename])
            end
          end
          code=((list.empty?)?(nil):("#{code},only:#{list.join(",")}"))
        end
        if code
          up=use_part
          new_usenames=[[:all]] if new_usenames.empty?
          new_uses={modname=>new_usenames}
          old_uses=up.env[:uses]
          up.env[:uses]=(old_uses)?(old_uses.merge(new_uses)):(new_uses)
          t=raw(code,:use_stmt,@srcfile,{:env=>env})
          t.parent=up
          up.e.push(t)
        end
      end
    end

    def varenv_chk(name,node,expected)
      n="#{name}"
      unless (varenv=node.env[n])
        fail "ERROR: '#{n}' not found in environment" if expected
      end
      [n,varenv]
    end

    def varenv_del(name,node=self,expected=true)
      n,varenv=varenv_chk(name,node,expected)
      node.env.delete(n)
    end

    def varenv_get(name,node=self,expected=true)
      n,varenv=varenv_chk(name,node,expected)
      varenv
    end

  end

  class NT < T

		def str0
      (e)?(e.map { |x| "#{x}" }.join):("")
		end

  end

  class List < NT

    def str0
      list_str
    end

  end

  class Stmt < NT

    def str0
			stmt(space)
    end

    def str1
      indent(strmemo)
    end

  end

  class Scoping_Unit < NT
  end

  # Out-of-order class definitions (must be defined before subclassed)

  class Io_Item_List < NT

    def items
      [e[0]]+e[1].e.reduce([]) { |m,x| m.push(x.item) }
    end

		def str0
			list_str
		end

  end

  class Io_Item_List_Pair < NT

    def item
      e[1]
		end

  end

  class Io_Spec_List < NT

    def access
      list_item(Io_Spec_Access)
    end

    def action
      list_item(Io_Spec_Action)
    end

    def blank
      list_item(Io_Spec_Blank)
    end

    def delim
      list_item(Io_Spec_Delim)
    end

    def direct
      list_item(Io_Spec_Direct)
    end

    def end
      list_item(Io_Spec_End)
    end

    def eor
      list_item(Io_Spec_Eor)
    end

    def err
      list_item(Io_Spec_Err)
    end

    def exist
      list_item(Io_Spec_Exist)
    end

    def form
      list_item(Io_Spec_Form)
    end

    def formatted
      list_item(Io_Spec_Formatted)
    end

    def iostat
      list_item(Io_Spec_Iostat)
    end

    def list_item(spec)
      return e[0] if e[0].is_a?(spec)
      e[1].e.each { |x| return x.e[1] if x.e[1].is_a?(spec) } if e[1]
      nil
    end

    def name
      list_item(Io_Spec_Name)
    end

    def named
      list_item(Io_Spec_Named)
    end

    def nextrec
      list_item(Io_Spec_Nextrec)
    end

    def nml
      if (io_spec_nml=list_item(Io_Spec_Nml))
        return io_spec_nml.rhs
      elsif e[0].is_a?(Io_Control_Spec_Unit_Nml)
        return e[0].nml
      end
      nil
    end

    def number
      list_item(Io_Spec_Number)
    end

    def opened
      list_item(Io_Spec_Opened)
    end

    def pad
      list_item(Io_Spec_Pad)
    end

    def position
      list_item(Io_Spec_Position)
    end

    def read
      list_item(Io_Spec_Read)
    end

    def readwrite
      list_item(Io_Spec_Readwrite)
    end

    def recl
      list_item(Io_Spec_Recl)
    end

    def sequential
      list_item(Io_Spec_Sequential)
    end

    def size
      list_item(Io_Spec_Size)
    end

    def str0
      list_str
    end

    def unformatted
      list_item(Io_Spec_Unformatted)
    end

    def unit
      if (io_spec_unit=list_item(Io_Spec_Unit))
        io_spec_unit.rhs
      else
        # If 'unit=' does not appear, the unit *must* be the first list item
        e[0].e[0]
      end
    end

    def write
      list_item(Io_Spec_Write)
    end

  end

  class Io_Stmt < NT

    def access
      spec_list.access
    end

    def action
      spec_list.action
    end

    def blank
      spec_list.blank
    end

    def delim
      spec_list.delim
    end

    def direct
      spec_list.direct
    end

    def end
      spec_list.end
    end

    def eor
      spec_list.eor
    end

    def err
      spec_list.err
    end

    def exist
      spec_list.exist
    end

    def form
      spec_list.form
    end

    def formatted
      spec_list.formatted
    end

    def input_items
      if is_a?(Read_Stmt_1) and e[5].is_a?(Input_Item_List)
        e[5].items
      elsif is_a?(Read_Stmt_2) and e[3].is_a?(Read_Stmt_Input_Item_List_Option)
        e[3].items
      else
        []
      end
    end

    def iostat
      spec_list.iostat
    end

    def name
      spec_list.name
    end

    def named
      spec_list.named
    end

    def number
      spec_list.number
    end

    def numbered
      spec_list.numbered
    end

    def opened
      spec_list.opened
    end

    def nextrec
      spec_list.nextrec
    end

    def nml
      spec_list.nml
    end

    def output_items
      if is_a?(Write_Stmt) and e[5].is_a?(Output_Item_List)
        e[5].items
      else
        []
      end
    end

    def pad
      spec_list.pad
    end

    def position
      spec_list.position
    end

    def read
      spec_list.read
    end

    def readwrite
      spec_list.readwrite
    end

    def recl
      spec_list.recl
    end

    def replace_input_item(old,new)
      input_items.each do |x|
        replace_element(new,:expr,old) if "#{x}"=="#{old}"
      end
    end

    def replace_output_item(old,new)
      output_items.each do |x|
        replace_element(new,:expr,old) if "#{x}"=="#{old}"
      end
    end

    def sequential
      spec_list.sequential
    end

    def size
      spec_list.size
    end

    def spec_list
      (e[3].is_a?(Io_Spec_List))?(e[3]):([])
    end

    def unformatted
      spec_list.unformatted
    end

    def unit
      spec_list.unit
    end

    def write
      spec_list.write
    end

  end

  # Grammar-supporting subclasses

  class AC_Implied_Do_Control < NT

    def str0
      s="#{e[0]}#{e[1]}#{e[2]}"
      s+="#{e[3].e[0]}#{e[3].e[1]}" if e[3].e
      s
    end

  end

  class AC_Value_List < NT

		def str0
			list_str
		end

  end

  class Access_Id_List < NT

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.name) }
		end

    def str0
      list_str
    end

  end

  class Access_Id_List_Pair < NT

    def name
      e[1]
		end

  end

  class Access_Spec < T

    def private?
      "#{text_value}"=="private"
    end

    def public?
      "#{text_value}"=="public"
    end

  end

  class Access_Stmt < Stmt

    def names
      (e[2].is_a?(Access_Stmt_Option))?(e[2].names):([])
    end

    def str0
      stmt("#{e[1]}#{e[2]}")
    end

  end

  class Access_Stmt_Option < NT

    def names
      e[1].names
    end

    def str0
      "#{ik(e[0],"::"," ")}#{e[1]}"
    end

  end

  class Actual_Arg_Spec_List < NT

		def str0
			list_str
		end

  end

  class Add_Operand < NT

    def str0
      "#{e[0]}"+((e[1].e)?("#{e[1].e[0]}#{e[1].e[1]}"):(""))
    end

  end

  class Allocatable_Stmt < Stmt

		def str0
			stmt("#{e[1]}#{ir(e[2],""," ")}#{e[3]}")
		end

  end

  class Allocate_Object < NT

    def item
      e[1]
    end

    def name
      e[1].name
    end

  end

  class Allocate_Object_List < NT

    def items
      e[1].e.reduce([e[0].item]) { |m,x| m.push(x.e[1].item) }
    end

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.e[1].name) }
    end

    def str0
      list_str
    end

  end

  class Allocate_Object_List_Pair < NT

    def item
      e[1].item
    end

    def name
      e[1].name
    end

  end

  class Allocate_Shape_Spec_List < NT

		def str0
			list_str
		end

  end

  class Allocate_Stmt < Stmt

    def items
      e[3].items
    end

    def names
      e[3].names
    end

    def str0
      cat_stmt
    end

  end

  class Allocation < NT

    def name
      e[0].name
    end

  end

  class Allocation_List < NT

    def items
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.e[1]) }
    end

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.e[1].name) }
    end

    def str0
      list_str
    end

  end

  class Alt_Return_Spec < NT
  end

  class Arithmetic_If_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]} #{e[5]}#{e[6]}#{e[7]}#{e[8]}#{e[9]}")
		end

  end

  class Array_Name < NT
  end

  class Array_Name_And_Deferred_Shape_Spec_List < NT

    def array_spec
      (e[1].respond_to?(:array_spec))?(e[1].array_spec):(nil)
    end

    def name
      "#{e[0]}"
    end

  end

  class Array_Name_And_Deferred_Shape_Spec_List_Pair < NT
  end

  class Array_Name_And_Spec < NT

    def name
      "#{e[0]}"
    end

    def spec
      e[2]
    end

  end

  class Array_Name_And_Spec_Pair < NT

    def name
      e[1].name
		end

  end

  class Array_Names_And_Deferred_Shape_Spec_Lists < NT

    def items
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.e[1]) }
    end

    def names
      e[1].e.reduce(["#{e[0].e[0]}"]) { |m,x| m.push("#{x.e[1].e[0]}") }
    end

    def str0
      list_str
    end

  end

  class Array_Names_And_Specs < NT

    def items
      e[1].e.reduce([e[0]]) { |m,x| m.push(x) }
    end

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.name) }
    end

    def str0
      list_str
    end

  end

  class Array_Section < NT

    def data_ref
      e[0]
    end

    def name
      data_ref.name
		end

    def subscript_list
      data_ref.subscript_list
    end

  end

  class Array_Spec < NT

    def spec
      e[0]
		end

  end

  class Assign_Stmt < Stmt
  end

  class Assigned_Goto_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{ik(e[3],","," ")}#{e[4]}")
		end

  end

  class Assignment_Stmt < Stmt

    def str0
      cat_stmt
    end

  end

  class Assumed_Shape_Spec < NT

    def abstract_bounds
      OpenStruct.new({:alb=>alb,:aub=>aub})
    end

    def abstract_boundslist
      abstract_bounds
    end

    def alb
      # abstract lower bound
      ("#{e[0]}".empty?)?("_assumed"):("_offset")
    end

    def aub
      # abstract upper bound
      "_assumed"
    end

  end

  class Assumed_Shape_Spec_List < Array_Spec

    def abstract_boundslist
      e[1].e.reduce([e[0].abstract_bounds]) { |m,x| m.push(x.abstract_bounds) }
    end

    def post
      ok=true
      if (entity_decl=ancestor(Entity_Decl))
        array_name="#{entity_decl.name}"
        ok=(env[:args] and env[:args].include?(array_name))?(true):(false)
      elsif (entity_decl=ancestor(Array_Name_And_Spec))
        array_name="#{entity_decl.name}"
        ok=(env[array_name]["lb1"]=="_deferred")?(false):(true)
      end
      unless ok
        code="#{self}"
        replace_element(code,:deferred_shape_spec_list)
        varenv=varenv_get(array_name)
        varenv.keys.each { |k| varenv[k]="_deferred" if k=~/[lu]b\d+/ }
      end
    end

    def str0
      list_str
    end

  end

  class Assumed_Shape_Spec_List_Pair < NT

    def abstract_bounds
      e[1].abstract_bounds
    end

  end

  class Assumed_Size_Spec < Array_Spec

    def abstract_bounds
      OpenStruct.new({:alb=>alb,:aub=>aub})
    end

    def abstract_boundslist
      abstract_explicit_boundslist+[abstract_bounds]
    end

    def abstract_explicit_boundslist
      (e[0].respond_to?(:abstract_boundslist))?(e[0].abstract_boundslist):([])
    end

    def alb
      # abstract lower bound
      ("#{e[1]}".empty?)?("_default"):(e[1].alb)
    end

    def aub
      # abstract upper bound
      "_assumed"
    end

  end

  class Assumed_Size_Spec_Pair < NT

    def abstract_boundslist
      e[0].abstract_boundslist
    end

  end

  class Attr_Spec_Allocatable < NT

    def allocatable?
      true
    end

  end

  class Attr_Spec_Base < NT

    def allocatable?
      attrany(:allocatable?)
    end

    def attrany(attr,e1=nil)
      (e1||e).reduce(false) { |m,x| m||=attrchk(x,attr) }
    end

    def dimension?
      attrany(:dimension?)
    end

    def parameter?
      attrany(:parameter?)
    end

    def private?
      attrany(:private?)
    end

    def public?
      attrany(:public?)
    end

  end

  class Attr_Spec_Dimension < NT

    def dimension?
      e[2]
		end

  end

  class Attr_Spec_List < Attr_Spec_Base
  end

  class Attr_Spec_List_Pair < Attr_Spec_Base
  end

  class Attr_Spec_List_Pairs < Attr_Spec_Base

    def allocatable?
      (e[0])?(attrany(:allocatable?,e[0].e)):(false)
    end

    def dimension?
      (e[0])?(attrany(:dimension?,e[0].e)):(false)
    end

    def parameter?
      (e[0])?(attrany(:parameter?,e[0].e)):(false)
    end

    def private?
      (e[0])?(attrany(:private?,e[0].e)):(false)
    end

    def public?
      (e[0])?(attrany(:public?,e[0].e)):(false)
    end

  end

  class Attr_Spec_Option < Attr_Spec_Base

    def allocatable?
      e[1].allocatable?
    end

    def dimension?
      e[1].dimension?
    end

    def parameter?
      e[1].parameter?
    end

  end

  class Attr_Spec_Parameter < NT

    def parameter?
      true
		end

  end

  class Backspace_Stmt_1 < Io_Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
		end

  end

  class Backspace_Stmt_2 < Io_Stmt

		def str0
			stmt("#{e[1]} #{e[2]}")
		end

  end

  class Block_Data < Scoping_Unit
  end

  class Block_Data_Name < NT
  end

  class Block_Data_Stmt < Stmt

    def str1
      s=strmemo
      block_right
      s
    end

  end

  class Block_Do_Construct < NT
  end

  class Call_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}")
		end

  end

  class Case_Construct_Name < NT
  end

  class Case_Stmt < Stmt

    def str1
      block_left
      s=strmemo
      block_right
      s
    end

  end

  class Case_Value_Range_List < NT

		def str0
			list_str
		end

  end

  class Close_Spec_List < Io_Spec_List
  end

  class Close_Spec_List_Pair < NT
  end

  class Close_Stmt < Io_Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
		end

  end

  class Common_Block_Name_And_Object_List < NT

		def str0
			"#{ir(e[0],""," ")}#{e[1]}#{e[2]}"
		end

  end

  class Common_Block_Name < NT

    def name
      e[0]
    end

  end

  class Common_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
		end

  end

  class Component_Attr_Spec_List < NT

		def str0
			list_str
		end

  end

  class Component_Decl_List < NT

		def str0
			list_str
		end

  end

  class Component_Def_Stmt < Stmt

		def str0
			stmt("#{e[1]}#{ir(e[2],""," ")}#{e[3]}")
		end

  end

  class Component_Name < NT
  end

  class Computed_Goto_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}#{ir(e[5],""," ")}#{e[6]}")
		end

  end

  class Connect_Spec_List < Io_Spec_List
  end

  class Connect_Spec_List_Pair < NT
  end

  class Contains_Stmt < Stmt

    def str1
      block_left
      s="\n#{indent(strmemo)}"
      block_right
      s
    end

  end

  class Continue_Stmt < Stmt
  end

  class Cycle_Stmt < Stmt
  end

  class Data_I_Do_Object_List < NT

		def str0
			list_str
		end

  end

  class Data_Ref < NT

    def name
      rightmost.name
    end

    def part_ref
      rightmost
    end

    def rightmost
      (e[1].e.empty?)?(e[0]):(e[1].e[-1].e[1])
    end

    def subscript_list
      part_ref.subscript_list
    end

    def str0
      e[1].e.reduce("#{e[0]}") { |m,x| m+"#{x.e[0]}#{x.e[1]}" }
    end

  end

  class Data_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}")
		end

  end

  class Data_Stmt_Object_List < NT

		def str0
			list_str
		end

  end

  class Data_Stmt_Value_List < NT

		def str0
			list_str
		end

  end

  class Deallocate_Stmt < Stmt

    def str0
      cat_stmt
    end

  end

  class Declaration_Constructs < NT

    def str0
      e.reduce("") { |m,x| m+"#{x}" }
    end

  end

  class Deferred_Shape_Spec < NT

    def abstract_bounds
      OpenStruct.new({:alb=>alb,:aub=>aub})
    end

    def alb
      # abstract lower bound
      "_deferred"
    end

    def aub
      # abstract upper bound
      "_deferred"
    end

  end

  class Deferred_Shape_Spec_List < Array_Spec

    def abstract_boundslist
      e[1].e.reduce([e[0].abstract_bounds]) { |m,x| m.push(x.abstract_bounds) }
    end

    def str0
      list_str
    end

  end

  class Deferred_Shape_Spec_List_Pair < NT

    def abstract_bounds
      e[1].abstract_bounds
    end

  end

  class Derived_Type_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{sb(e[2])} #{e[3]}")
    end

    def str1
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Dimension_Stmt < Stmt

		def str0
			stmt("#{e[1]}#{ir(e[2],""," ")}#{e[3]}")
		end

  end

  class Do_Body < NT
  end

  class Do_Construct_Name < NT
  end

  class Do_Term_Action_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class Do_Term_Shared_Stmt < Stmt

    def label
      "#{e[1].e[0]}"
    end

    def str1
      block_left
      n=self
      while (n=n.ancestor(Outer_Shared_Do_Construct))
        block_left if n.label==label
      end
      indent(strmemo)
    end

  end

  class Double_Colon < NT
  end

  class Dummy_Arg_List < NT

    def str0
      list_str
    end

  end

  class Dummy_Arg_List_Pair < NT
  end

  class Dummy_Arg_Name < NT
  end

  class Dummy_Arg_Name_List < NT

    def names
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.name) }
    end

    def str0
      list_str
    end

  end

  class Dummy_Arg_Name_List_Pair < NT

    def name
      e[1]
    end

  end

  class Else_If_Stmt < Stmt

    def str0
      stmt("#{e[2]} #{e[3]}#{e[4]}#{e[5]} #{e[6]}")
    end

    def str1
      block_left
      s="\n#{indent(strmemo)}"
      block_right
      s
    end

  end

  class Else_Stmt < Stmt

    def str1
      block_left
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Elsewhere_Stmt < Stmt

    def str1
      block_left
      s=strmemo
      block_right
      s
    end

  end

  class End_Block_Data_Option < NT

		def str0
			space(true)
		end

  end

  class End_Block_Data_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class End_Do_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class End_Function_Option < NT

    def str0
			space(true)
    end

  end

  class End_Function_Stmt < Stmt

    def str1
      block_left
      "#{indent(strmemo)}\n"
    end

  end

  class End_If_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class End_Interface_Stmt < Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{sb(e[3])}")
    end

    def str1
      block_left
      "#{indent(strmemo)}\n"
    end

  end

  class End_Module_Option < NT

		def str0
			space(true)
		end

  end

  class End_Module_Stmt < Stmt

    def str1
      block_left
      "#{indent(strmemo)}\n"
    end

  end

  class End_Program_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{sb(e[3])}#{sb(e[4])}")
    end

    def str1
      block_left
      "\n#{indent(strmemo)}"
    end

  end

  class End_Select_Stmt < Stmt

    def str1
      block_left
      block_left
      indent(strmemo)
    end

  end

  class End_Subroutine_Option < NT

    def str0
			space(true)
    end

  end

  class End_Subroutine_Stmt < Stmt

    def str1
      block_left
      "\n#{indent(strmemo)}\n"
    end

  end

  class End_Type_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class End_Where_Stmt < Stmt

    def str1
      block_left
      indent(strmemo)
    end

  end

  class Endfile_Stmt_1 < Io_Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
		end

  end

  class Endfile_Stmt_2 < Io_Stmt

		def str0
			stmt("#{e[1]} #{e[2]}")
		end

  end

  class Entity_Decl < NT

    def name
      e[0].name
    end

    def attrs(distribute)
      _attrs={}
      if e[1].is_a?(Entity_Decl_Array_Spec)
        array_attrs(e[1].e[1].e[0],_attrs,distribute)
      end
      _attrs["sort"]=((array?)?("_array"):("_scalar"))
      {name=>_attrs}
    end

  end

  class Entity_Decl_1 < Entity_Decl

    def array?
      e[1].is_a?(Entity_Decl_Array_Spec)
    end

  end

  class Entity_Decl_2 < Entity_Decl

    def array?
      # need to determine array/scalar spec of named function here?
      false
		end
  end

  class Entity_Decl_Array_Spec < NT
  end

  class Entity_Decl_List < NT

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.name) }
    end

    def varattrs(distribute)
      e[0].attrs(distribute).merge(e[1].attrs(distribute))
    end

  end

  class Entity_Decl_List_Pair < NT

    def array?
      e[1].array?
    end

    def name
      e[1].name
    end

    def attrs(distribute)
      e[1].attrs(distribute)
    end

  end

  class Entity_Decl_List_Pairs < NT

    def attrs(distribute)
      e.reduce({}) { |m,x| m.merge(x.attrs(distribute)) }
    end

  end

  class Entry_Name < NT
  end

  class Entry_Stmt < Stmt

		def str0
			stmt("#{e[1]} #{e[2]}#{e[3]}#{sb(e[4])}")
		end

  end

  class Equivalence_Set_List < NT

		def str0
			list_str
		end

  end

  class Equivalence_Stmt < Stmt
  end

  class Executable_Construct_Action_Stmt < Stmt

    def str1
      indent(strmemo)
    end

  end

  class Execution_Part < NT
  end

  class Execution_Part_Construct < NT
  end

  class Exit_Stmt < Stmt
  end

  class Explicit_Shape_Spec < NT

    def abstract_bounds
      OpenStruct.new({:alb=>alb,:aub=>aub})
    end

    def alb
      # abstract lower bound
      "_explicit"
    end

    def aub
      # abstract upperbound
      "_explicit"
    end

    def concrete_bounds
      OpenStruct.new({:clb=>clb,:cub=>cub})
    end

    def clb
      (e[0].respond_to?(:clb))?(e[0].clb):("1")
    end

    def cub
      e[1].cub
    end

  end

  class Explicit_Shape_Spec_List < Array_Spec

    def abstract_boundslist
      e[1].e.reduce([e[0].abstract_bounds]) { |m,x| m.push(x.abstract_bounds) }
    end

    def concrete_boundslist
      e[1].e.reduce([e[0].concrete_bounds]) { |m,x| m.push(x.concrete_bounds) }
    end

    def str0
      list_str
    end

  end

  class Explicit_Shape_Spec_List_Pair < NT

    def abstract_bounds
      e[1].abstract_bounds
    end

    def concrete_bounds
      e[1].concrete_bounds
    end

  end

  class Expr < NT

    def str0
      "#{e[0]}"+((e[1].e)?("#{e[1].e[0]}#{e[1].e[1]}"):(""))
    end

  end

  class Expr_List < NT

		def str0
			list_str
		end

  end

  class External_File_Unit < NT
  end

  class External_Name < NT
  end

  class External_Name_List < NT

		def str0
			list_str
		end

  end

  class External_Stmt < Stmt
  end

  class Format_Stmt < Stmt
  end

  class Function_Name < NT

    def name
      e[0]
    end

  end

  class Function_Prefix < NT

    def any?(o)
      fail "ERROR: Expected string or class" unless o.is_a?(Symbol) or o.is_a?(Class)
      e.each do |x|
        return x if ((o.is_a?(Symbol))?("#{x}"=="#{o}"):(x.is_a?(o)))
      end
      nil
    end

    def elemental?
      any?(:elemental)
    end

    def pure?
      any?(:pure)
    end

    def recursive?
      any?(:recursive)
    end

		def str0
			e.map { |x| "#{x}" }.join(" ")
		end

    def type_spec
      any?(Type_Spec)
    end

  end

  class Function_Reference < NT

    def name
      e[0]
    end

  end

  class Function_Stmt < Stmt

    def elemental?
      function_prefix.elemental?
    end

    def function_name
      e[3]
    end

    def function_prefix
      e[1]
    end

    def name
      e[3].name
    end

    def pure?
      function_prefix.pure?
    end

    def recursive?
      function_prefix.recursive?
    end

    def str0
      stmt("#{sa(e[1])}#{e[2]} #{e[3]}#{e[4]}#{e[5]}#{e[6]}#{sb(e[7])}")
    end

    def str1
      s="\n#{indent(strmemo)}"
      block_right
      s
    end

    def type_spec
      (function_prefix.is_a?(Function_Prefix))?(function_prefix.type_spec):(nil)
    end

  end

  class Function_Subprogram < Scoping_Unit

    def elemental?
      function_stmt.elemental?
    end

    def function_name
      function_stmt.function_name
    end

    def function_prefix
      function_stmt.function_prefix
    end

    def function_stmt
      e[0]
    end

    def name
      e[0].name
    end

    def pure?
      function_stmt.pure?
    end

    def recursive?
      function_stmt.recursive?
    end

    def function_stmt_type_spec
      function_stmt.type_spec
    end

  end

  class Generic_Name < NT

    def name
      e[0]
    end

  end

  class Generic_Spec < NT

    def localname
      usename
    end

    def name
      usename
    end

    def str0
      "#{e[0]} #{e[1]}#{e[2]}#{e[3]}"
    end

    def usename
      "#{e[2]}"
    end

  end

  class Goto_Stmt < Stmt
  end

  class If_Construct < NT
  end

  class If_Construct_Name < NT
  end

  class If_Stmt < Stmt

    def action
      "#{e[5]}".strip
    end

    def prefix
      "#{e[1]} #{e[2]}#{e[3]}#{e[4]}"
    end

    def str0
      stmt("#{prefix} #{action}")
    end

  end

  class If_Then_Stmt < Stmt

    def str1
      s=indent(strmemo)
      block_right
      s
    end

    def str0
      stmt("#{sa(e[1])}#{e[2]} #{e[3]}#{e[4]}#{e[5]} #{e[6]}")
    end

  end

  class Implicit_None_Stmt < Stmt

    def str1
      "#{indent(strmemo)}\n"
    end

  end

  class Implicit_Part < NT
  end

  class Implicit_Spec_List < NT

    def str0
      list_str
    end

  end

  class Implicit_Spec_List_Pair < NT
  end

  class Implicit_Stmt < Stmt
  end

  class Initialization < NT

    def str0
      "#{e[0]}#{e[1]}"
    end

  end

  class Initialization_1 < Initialization
  end

  class Initialization_2 < Initialization
  end

  class Inner_Shared_Do_Construct < NT

    def label
      e[0].label
    end

  end

  class Input_Item_List < Io_Item_List
  end

  class Input_Item_List_Pair < Io_Item_List_Pair
  end

  class Inquire_Spec_List < Io_Spec_List
  end

  class Inquire_Stmt_1 < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
    end

  end

  class Inquire_Stmt_2 < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}#{e[7]}")
    end

  end

  class Intent_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{e[2]}#{e[3]}#{e[4]}#{ik(e[5],"::"," ")}#{e[6]}")
    end

  end

  class Interface_Body < NT
  end

  class Interface_Body_1 < Interface_Body
  end

  class Interface_Body_2 < Interface_Body
  end

  class Interface_Stmt < Stmt

    def str1
      s="\n#{strmemo}"
      block_right
      s
    end
  end

  class Internal_File_Unit < NT
  end

  class Internal_Subprograms < NT


    def str0
      e.map { |x| "#{x}" }.join
    end

  end

  class Intrinsic_Procedure_Name < NT
  end

  class Intrinsic_Procedure_Name_List < NT

    def str0
      list_str
    end

  end

  class Intrinsic_Stmt < Stmt
  end

  class Io_Control_Spec_List < Io_Spec_List
  end

  class Io_Control_Spec_List_Pair < NT
  end

  class Io_Control_Spec_Unit_Nml < NT

    def unit
      e[0]
    end

    def nml
      e[2]
    end

  end

  class Io_Implied_Do_Object_List < NT

    def str0
      list_str
    end

  end

  class Io_Spec < NT

    def relabel_spec(spec)
      old=rhs
      new=label_create
      replace_element("#{new}",:label,e[2])
      [old,new]
    end

    def rhs
      e[2]
    end

  end

  class Io_Spec_Access < Io_Spec
  end

  class Io_Spec_Action < Io_Spec
  end

  class Io_Spec_Blank < Io_Spec
  end

  class Io_Spec_Delim < Io_Spec
  end

  class Io_Spec_Direct < Io_Spec
  end

  class Io_Spec_End < Io_Spec

    def relabel
      relabel_spec(:end)
    end

  end

  class Io_Spec_Eor < Io_Spec

    def relabel
      relabel_spec(:eor)
    end

  end

  class Io_Spec_Err < Io_Spec

    def relabel
      relabel_spec(:err)
    end

  end

  class Io_Spec_Exist < Io_Spec
  end

  class Io_Spec_Form < Io_Spec
  end

  class Io_Spec_Formatted < Io_Spec
  end

  class Io_Spec_Iostat < Io_Spec
  end

  class Io_Spec_Name < Io_Spec
  end

  class Io_Spec_Named < Io_Spec
  end

  class Io_Spec_Nextrec < Io_Spec
  end

  class Io_Spec_Nml < Io_Spec
  end

  class Io_Spec_Number < Io_Spec
  end

  class Io_Spec_Opened < Io_Spec
  end

  class Io_Spec_Pad < Io_Spec
  end

  class Io_Spec_Position < Io_Spec
  end

  class Io_Spec_Read < Io_Spec
  end

  class Io_Spec_Readwrite < Io_Spec
  end

  class Io_Spec_Recl < Io_Spec
  end

  class Io_Spec_Sequential < Io_Spec
  end

  class Io_Spec_Size < Io_Spec
  end

  class Io_Spec_Unformatted < Io_Spec
  end

  class Io_Spec_Unit < Io_Spec

    def unit
      e[2]
    end

  end

  class Io_Spec_Write < Io_Spec
  end

  class Kind_Selector < NT

    def kind
      "#{e[2]}"
    end

  end

  class Label < NT

    def str0
      "#{text_value.to_i}"
    end

  end

  class Label_Assign < Label
  end

  class Label_Branch < Label
  end

  class Label_Format < Label
  end

  class Label_Do_Stmt < Stmt

    def label
      "#{e[3]}"
    end

    def str0
      stmt("#{sa(e[1])}#{e[2]} #{e[3]}#{e[4]}")
    end

    def str1
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Label_List < NT

    def labels
      e[1].e.reduce([e[0].label]) { |m,x| m.push(x.label) }
    end

    def str0
      list_str
    end

  end

  class Label_List_Pair < NT

    def label
      e[1]
    end

  end

  class Label_Stmt < NT
  end

  class Letter_Spec_List < NT

    def str0
      list_str
    end

  end

  class Local_Name < NT
  end

  class Loop_Control < NT
  end

  class Loop_Control_1 < Loop_Control

    def str0
      "#{ir(e[0],""," ")}#{e[1]}#{e[2]}#{e[3]}#{e[4]}#{e[5]}"
    end

  end

  class Loop_Control_2 < Loop_Control

    def str0
      "#{ir(e[0],""," ")}#{e[1]} #{e[2]}#{e[3]}#{e[4]}"
    end

  end

  class Loop_Control_Pair < NT

    def value
      e[1]
    end

  end

  class Lower_Bound_Pair < NT

    def alb
      # abstract lower bound
      clb
    end

    def clb
      # concrete lower bound
      "#{e[0]}"
    end

  end

  class Main_Program < Scoping_Unit

    def execution_part
      (e[2].is_a?(Execution_Part))?(e[2]):(nil)
    end

  end

  class Module < Scoping_Unit

    def name
      e[0].name
    end

    def subprograms
      (e[2].is_a?(Module_Subprogram_Part))?(e[2].subprograms):([])
    end

  end

  class Module_Name < NT
  end

  class Module_Procedure_Stmt < Stmt
  end

  class Module_Stmt < Stmt

    def name
      "#{e[2]}"
    end

    def str1
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Module_Subprogram_Function < NT

    def env
      e[0].env
    end

    def name
      e[0].name
    end

  end

  class Module_Subprogram_Part < NT

    def subprograms
      e[1].e
    end

    def str0
      "#{e[0]}#{e[1].e.reduce("") { |m,x| m+="#{x}" } }"
    end

  end

  class Module_Subprogram_Subroutine < NT

    def env
      e[0].env
    end

    def name
      e[0].name
    end

  end

  class Mult_Operand < NT

    def str0
      "#{e[0]}#{e[1]}"
    end

  end

  class Name < NT

    def name
      "#{self}"
    end

    def str0
      s="#{e[0]}"
      if e[1]
        s=e[1].e.reduce(s) { |m,x| s+="#{x}" }
      end
      s
    end

  end

  class Named_Constant < NT
  end

  class Named_Constant_Def < NT

    def name
      e[0]
    end

  end

  class Named_Constant_Def_List < NT

    def names
      [e[0].name]+e[1].e.reduce([]) { |m,x| m.push(x.e[1].name) }
    end

    def str0
      list_str
    end

  end

  class Namelist_Group_Name < NT

    def name
      e[0]
    end

  end

  class Namelist_Group_Object_List < NT

    def objects
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.object) }
    end

    def str0
      list_str
    end

  end

  class Namelist_Group_Object_List_Pair < NT

    def object
      e[1]
    end

  end

  class Namelist_Group_Set < NT

    def name
      e[1].name
    end

    def objects
      e[3].objects
    end

    def set
      [name,objects]
    end

    def str0
      "#{e[0]}#{e[1]}#{e[2]} #{e[3]}"
    end

  end

  class Namelist_Group_Set_Pair < NT

    def name
      e[1].name
    end

    def set
      e[1]
    end

    def str0
      "#{ir(e[0],""," ")}#{e[1]}"
    end

  end

  class Namelist_Group_Sets < NT

    def names
      sets.reduce([]) { |m,x| m.push(x.name) }
    end

    def sets
      e.reduce([]) { |m,x| m.push(x.set) }
    end

  end

  class Namelist_Stmt < Stmt

    def sets
      e[3].sets.push(e[2].set)
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}")
    end

  end

  class Nonblock_Do_Construct < NT

    def label
      e[0].label
    end

  end

  class Nonlabel_Do_Stmt < Stmt

    def str0
      stmt("#{sa(e[1])}#{e[2]}#{e[3]}")
    end

    def str1
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Nullify_Stmt < Stmt

    def str0
      cat_stmt
    end

  end

  class Object_Name < NT

    def name
      e[0]
    end

  end

  class Object_Name_And_Spec_List < NT

    def name
      e[0].name
    end

  end

  class Object_Name_And_Spec_List_Pair < NT

    def name
      e[1].name
    end

  end

  class Object_Names_And_Spec_Lists < NT

    def names
      e[1].e.reduce([e[0].name]) { |m,x| m.push(x.name) }
    end

  end

  class Only < NT

    def localname
      (e[0].is_a?(Only_Option))?(e[0].localname):(usename)
    end

    def usename
      "#{e[1]}"
    end

  end

  class Only_List < NT

    def localnames
      e[1].e.reduce([e[0].localname]) { |m,x| m.push(x.localname) }
    end

    def usenames
      e[1].e.reduce([e[0].usename]) { |m,x| m.push(x.usename) }
    end

    def str0
      list_str
    end

  end

  class Only_List_Pair < NT

    def localname
      e[1].localname
    end

    def usename
      e[1].usename
    end

  end

  class Only_Option < NT

    def localname
      "#{e[0]}"
    end

  end

  class Open_Stmt < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
    end

  end

  class Optional_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{ik(e[2],"::"," ")}#{e[3]}")
    end

  end

  class Outer_Shared_Do_Construct < NT

    def label
      e[0].label
    end

  end

  class Output_Item_List < Io_Item_List
  end

  class Output_Item_List_Pair < Io_Item_List_Pair
  end

  class Parameter_Stmt < Stmt

    def str0
      "#{e[1]} #{e[2]}#{e[3]}#{e[4]}"
    end

    def str1
      "#{indent(strmemo)}\n"
    end

  end

  class Parenthesized_Args < NT
  end

  class Parenthesized_Deferred_Shape_Spec_List < NT

    def abstract_boundslist
      e[1].abstract_boundslist
    end

    def array_spec
      e[1]
    end

  end

  class Parenthesized_Explicit_Shape_Spec_List < NT

    def abstract_boundslist
      e[1].abstract_boundslist
    end

  end

  class Parenthesized_Section_Subscript_List < NT

    def subscript_list
      e[1].subscript_list
    end

  end

  class Part_Name < NT
  end

  class Part_Ref < NT

    def name
      part_name.name
    end

    def part_name
      e[0]
    end

    def subscript_list
      (e[1].is_a?(Parenthesized_Section_Subscript_List))?(e[1].subscript_list):([])
    end

  end

  class Pause_Stmt < Stmt
  end

  class Pointer_Assignment_Stmt < Stmt

    def str0
      cat_stmt
    end

  end

  class Pointer_Object_List < NT

    def str0
      list_str
    end

  end

  class Pointer_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{ir(e[2],""," ")}#{e[3]}")
    end

  end

  class Position_Spec_List < NT

    def str0
      list_str
    end

  end

  class Position_Spec_List_Pair < NT
  end

  class Power_Op < T
  end

  class Power_Op_Option < NT
  end

  class Print_Stmt < Io_Stmt

    def output_items
      (e[3].is_a?(Print_Stmt_Output_Item_List))?(e[3].items):([])
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}")
    end

  end

  class Print_Stmt_Output_Item_List < NT

    def items
      output_item_list.items
    end

    def output_item_list
      e[1]
    end

    def str0
      "#{e[0]}#{e[1]}"
    end

  end

  class Private_Sequence_Stmt < Stmt

    def str0
      cat_stmt
    end

  end

  class Procedure_Name < NT
  end

  class Procedure_Name_List < NT

    def str0
      list_str
    end

  end

  class Program_Name < NT
  end

  class Program_Stmt < Stmt

    def str1
      s=indent(strmemo)
      block_right
      s
    end

  end

  class Program_Units < NT

    def str0
      e.reduce("") { |m,x| m+="#{x}\n" }.chomp
    end

  end

  class Read_Stmt < Io_Stmt
  end

  class Read_Stmt_1 < Read_Stmt

    def items
      (e[5].is_a?(Input_Item_List))?(e[5].items):([])
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}#{sb(e[5])}")
    end

  end

  class Read_Stmt_2 < Read_Stmt

    def items
      (e[3].is_a?(Read_Stmt_Input_Item_List_Option))?(e[3].items):([])
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}")
    end

  end

  class Read_Stmt_Input_Item_List_Option

    def items
      e[1].items
    end

  end

  class Rename < NT

    def localname
      "#{e[0]}"
    end

    def usename
      "#{e[2]}"
    end

  end

  class Rename_List < NT

    def localnames
      e[1].e.reduce([e[0].localname]) { |m,x| m.push(x.localname) }
    end

    def usenames
      e[1].e.reduce([e[0].usename]) { |m,x| m.push(x.usename) }
    end

    def str0
      list_str
    end

  end

  class Rename_List_Pair < NT

    def localname
      e[1].localname
    end

    def usename
      e[1].usename
    end

  end

  class Rename_List_Option < NT

    def localnames
      e[1].localnames
    end

    def usenames
      e[1].usenames
    end

  end

  class Result_Name < NT

    def name
      e[0]
    end

  end

  class Result_Option < NT

    def name
      e[2].name
    end

  end

  class Return_Stmt < Stmt

    def str0
      space(true)
    end

  end

  class Rewind_Stmt_1 < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
    end

  end

  class Rewind_Stmt_2 < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}")
    end

  end
  class Save_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{e[2]}")
    end

  end

  class Save_Stmt_Entity_List < NT

    def names
      e[1].names
    end

    def str0
      "#{ir(e[0],""," ")}#{e[1]}"
    end

  end

  class Saved_Entity_1 < NT

    def name
      e[0].name
    end

  end

  class Saved_Entity_2 < NT

    def name
      e[1].name
    end

  end

  class Saved_Entity_List < NT

    def names
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.name) }
    end

    def str0
      list_str
    end

  end

  class Saved_Entity_List_Pair < NT

    def name
      e[1].name
    end

  end

  class Section_Subscript_List < NT

    def subscript_list
      e[1].elements.reduce([e[0]]) { |m,x| m.push(x.e[1]) }
    end

    def str0
      list_str
    end

  end

  class Select_Case_Stmt < Stmt

    def str0
      stmt("#{sa(e[1])}#{e[2]} #{e[3]} #{e[4]}#{e[5]}#{e[6]}")
    end

    def str1
      s=strmemo
      block_right
      block_right
      s
    end

  end

  class Specification_Part < NT

    def str1
      "\n#{strmemo}\n"
    end

  end

  class Star_Int < NT

    def kind
      "#{e[1]}"
    end

  end

  class Stmt_Function_Stmt < Stmt

    def name
      "#{e[1]}"
    end

    def str0
      cat_stmt
    end

  end

  class Stop_Stmt < Stmt
  end

  class Subroutine_Name < NT

    def name
      e[0]
    end

  end

  class Subroutine_Prefix < NT

    def str0
      e.map { |x| "#{x}" }.join(" ")
    end

  end

  class Subroutine_Subprogram < Scoping_Unit

    def name
      e[0].name
    end

  end

  class Subroutine_Stmt < Stmt

    def name
      e[3].name
    end

    def str0
      stmt("#{sa(e[1])}#{e[2]} #{e[3]}#{e[4]}")
    end

    def str1
      s="\n#{indent(strmemo)}"
      block_right
      s
    end

  end

  class Subscript < NT

    def subscript
      e[0]
    end

  end

  class Subscript_Triplet < NT

    def lower
      (e[0].is_a?(Subscript))?(e[0]):(nil)
    end

    def stride
      (e[3].is_a?(Subscript_Triplet_Stride_Option))?(e[3].stride):(1)
    end

    def upper
      (e[2].is_a?(Subscript))?(e[2]):(nil)
    end

  end

  class Subscript_Triplet_Stride_Option < NT

    def stride
      e[1]
    end

  end

  class Substring < NT

    def name
      e[0].name
    end

  end

  class Target_Object_List < NT

    def objects
      e[1].e.reduce([e[0]]) { |m,x| m.push(x.e[1]) }
    end

    def str0
      e[1].e.reduce("#{e[0]}") { |m,x| m+"#{x}" }
    end

  end

  class Target_Object_List_Pair < NT
  end

  class Target_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{ir(e[2],""," ")}#{e[3]}")
    end

  end

  class Type_Declaration_Stmt < Stmt

    def str0
      stmt("#{e[1]}#{ir(e[2],"",ik(e[1],","," "))}#{e[3]}")
    end

  end

  class Type_Name < NT
  end

  class Type_Spec < NT

    def derived?
      "#{e[0]}"=="type"
    end

    def kind
      return (e[1].respond_to?(:kind))?(e[1].kind):("_default")
    end

    def type
      (derived?)?("#{e[2]}"):("#{e[0]}")
    end

  end

  class Upper_Bound < NT

    def aub
      # abstract upper bound
      cub
    end

    def cub
      # concrete upper bound
      "#{e[0]}"
    end

  end

  class Use_Name < NT

    def name
      e[0]
    end

  end

  class Use_Part < NT

    def str1
      "\n#{strmemo}\n"
    end

  end

  class Use_Stmt < Stmt

    def modulename
      "#{e[2]}"
    end

  end

  class Use_Stmt_1 < Use_Stmt

    def localnames
      e[3].localnames
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}")
    end

    def usenames
      e[3].usenames
    end

  end

  class Use_Stmt_2 < Use_Stmt

    def localnames
      e[6].localnames
    end

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}")
    end

    def usenames
      e[6].usenames
    end

  end

  class Variable_Name < NT

    def name
      e[0]
    end

  end

  class Vector_Subscript < NT

    def subscript
      e[0]
    end

  end

  class Where_Construct_Stmt < Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}")
    end

    def str1
      s=strmemo
      block_right
      s
    end

  end

  class Where_Stmt < Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]} #{e[6]}".strip)
    end

  end

  class Write_Stmt < Io_Stmt

    def str0
      stmt("#{e[1]} #{e[2]}#{e[3]}#{e[4]}#{sb(e[5])}")
    end

  end

end
