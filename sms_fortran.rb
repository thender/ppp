require "set"

module Fortran

  def sp_do_construct(do_construct)
    iterator=do_construct.do_stmt.do_variable
    if (p=env[:sms_parallel])
      p.vars.each do |x|
        if x.include?("#{iterator}")
          do_construct.metadata[:parallel]=true
        end
      end
    end
    true
  end

  def sp_sms_barrier
    nest_check("sms$barrier","sms$serial",sms_serial)
    true
  end

  def sp_sms_comm_rank
    true
  end

  def sp_sms_comm_size
    true
  end

  def sp_sms_compare_var
    nest_check("sms$compare_var","sms$serial",sms_serial)
    true
  end

  def sp_sms_create_decomp
    nest_check("sms$create_decomp","sms$serial",sms_serial)
    true
  end

  def sp_sms_distribute_begin(sms_decomp_name,sms_distribute_dims)

    # Do not push an environment here. The declarations that appear inside a
    # distribute region belong to the environment belonging to the enclosing
    # scoping unit.

    efail "Already inside sms$distribute region" if @distribute
    @distribute={"decomp"=>"#{sms_decomp_name}","dim"=>[]}
    sms_distribute_dims.dims.each { |x| @distribute["dim"].push(x) }
    true
  end

  def sp_sms_exchange
    nest_check("sms$exchange","sms$serial",sms_serial)
    true
  end

  def sp_sms_exchange_begin
    nest_check("sms$exchange_begin","sms$serial",sms_serial)
    true
  end

  def sp_sms_exchange_end
    nest_check("sms$exchange_end","sms$serial",sms_serial)
    true
  end

  def sp_sms_distribute_end

    # Do not pop the environment stack here, because the matching 'begin' does
    # not push one.

    efail "Not inside sms$distribute region" unless @distribute
    @distribute=nil
    true
  end

  def sp_sms_halo_comp
    envpop(false)
    true
  end

  def sp_sms_halo_comp_begin(halo_comp_pairs,sidevar_option)
    efail "sms$halo_comp invalid outside sms$parallel region" unless sms_parallel
    efail "Already inside sms$halo_comp region" if sms_halo_comp
    envpush(false)
    dims={}
    dims["1"]=halo_comp_pairs.e[0]
    dims["2"]=halo_comp_pairs.e[1].e[1] if halo_comp_pairs.e[1].e
    dims["3"]=halo_comp_pairs.e[2].e[1] if halo_comp_pairs.e[2].e
    halo_comp_hash={}
    dims.each do |k,v|
      halo_comp_hash[k]=OpenStruct.new({:lo=>"#{v.lo}",:up=>"#{v.up}"})
    end
    if (sidevar_option.is_a?(SMS_Halo_Comp_Sidevar_Option))
      halo_comp_hash[:sidevar]="#{sidevar_option.sidevar}"
    end
    env[:sms_halo_comp]=OpenStruct.new(halo_comp_hash)
    true
  end

  def sp_sms_halo_comp_end
    efail "Not inside sms$halo_comp region" unless sms_halo_comp
    true
  end

  def sp_sms_ignore
    envpop(false)
    true
  end

  def sp_sms_ignore_begin
    nest_check("sms$ignore","sms$ignore",sms_ignore)
    nest_check("sms$ignore","sms$serial",sms_serial)
    envpush(false)
    env[:sms_ignore]=true
    true
  end

  def sp_sms_ignore_end
    efail "Not inside sms$ignore region" unless sms_ignore
    true
  end

  def sp_sms_parallel
    envpop(false)
    true
  end

  def sp_sms_parallel_begin(sms_decomp_name,sms_parallel_var_lists)
    nest_check("sms$parallel","sms$ignore",sms_ignore)
    nest_check("sms$parallel","sms$parallel",sms_parallel)
    nest_check("sms$parallel","sms$serial",sms_serial)
    envpush(false)
    env[:sms_parallel]=OpenStruct.new({:decomp=>"#{sms_decomp_name}",:vars=>sms_parallel_var_lists.vars})
    true
  end

  def sp_sms_parallel_end
    efail "Not inside sms$parallel region" unless sms_parallel
    true
  end

  def sp_sms_reduce
    nest_check("sms$reduce","sms$serial",sms_serial)
    true
  end

  def sp_sms_serial
    envpop(false)
    true
  end

  def sp_sms_serial_begin
    nest_check("sms$serial","sms$serial",sms_serial)
    nest_check("sms$serial","sms$ignore",sms_ignore)
    envpush(false)
    env[:sms_serial]=true
    true
  end

  def sp_sms_serial_end
    efail "Not inside sms$serial region" unless sms_serial
    true
  end

  def sp_sms_set_communicator
    nest_check("sms$set_communicator","sms$serial",sms_serial)
    true
  end

  def sp_sms_start
    nest_check("sms$start","sms$serial",sms_serial)
    true
  end

  def sp_sms_stop
    nest_check("sms$stop","sms$serial",sms_serial)
    true
  end

  def sp_sms_to_local
    envpop(false)
    true
  end

  def sp_sms_to_local_begin(sms_decomp_name,sms_to_local_lists)
    nest_check("sms$to_local","sms$to_local",sms_to_local)
    nest_check("sms$to_local","sms$serial",sms_serial)
    envpush(false)
    env[:sms_to_local]=sms_to_local_lists.vars.each do |var,props|
      props.dh="#{sms_decomp_name}"
    end
    true
  end

  def sp_sms_to_local_end
    efail "Not inside sms$to_local region" unless sms_to_local
    true
  end

  def sp_sms_unstructured_grid
    nest_check("sms$unstructured_grid","sms$serial",sms_serial)
    true
  end

  def sp_sms_unstructured_print_timers
    nest_check("sms$unstructured_print_timers","sms$serial",sms_serial)
    true
  end

  def sp_sms_zerotimers
    nest_check("sms$zero_timers","sms$serial",sms_serial)
    true
  end

  # Modules

  module Array_Translation

    def translate

      def getbound(var,dim,lu,cb=nil)
        varenv=env[var]
        return "#{cb}" unless (dd=decdim(varenv,dim))
        dh=varenv["decomp"]
        use(sms_decompmod) if dh
        nl="#{dh}__nestlevel"
        a1="#{dh}__#{(lu==:l)?('s'):('e')}1"
        a2="#{dh}__#{(lu==:l)?('low'):('upper')}bounds(#{dd},#{nl})"
        "#{a1}("+((cb)?("#{cb}"):("#{a2}"))+",0,#{nl})"
      end

      return if omp_parallel_loop or sms_ignore or sms_parallel_loop or sms_serial
      var="#{name}"
      if inside?(Assignment_Stmt,Where_Construct,Where_Stmt)
        if (fn=ancestor(Function_Reference))       # we're an actual arg
          return if not (range=intrinsic(fn.name)) # fn is not intrinsic
          return if range==:complete               # complete array arg ok
        end
        efail "'#{var}' not found in environment" unless (varenv=env[var])
        return unless varenv["decomp"]
        if defined?(range) and range==:error
          efail "Distributed-arrary argument '#{var}' incompatible with intrinsic procedure '#{fn.name}'"
        end
        bounds=[]
        sl=subscript_list
        (1..varenv["dims"]).each do |dim|
          if sl and (s=sl[dim-1])
            if s.is_a?(Subscript)
              bounds[dim-1]="#{s.subscript}"
            elsif s.is_a?(Subscript_Triplet)
              b=getbound(var,dim,:l,s.lower)+":"+getbound(var,dim,:u,s.upper)
              b+=":#{s.stride}" if s.stride and "#{s.stride}"!="1"
              bounds[dim-1]=b
            elsif s.is_a?(Vector_Subscript)
              ifail "in Array_Translation#translate: Please report to developers."
            else
              bounds[dim-1]="#{s}"
            end
          else
            bounds[dim-1]=getbound(var,dim,:l)+":"+getbound(var,dim,:u)
          end
        end
        boundslist=(1..varenv["dims"]).map{ |dim| bounds[dim-1] }.join(",")
        code="#{var}(#{boundslist})"
        replace_element(code,:variable)
      elsif (iostmt=ancestor(Io_Stmt))
        if known_distributed(var)
          subscript="#{self}".sub(/^#{Regexp.escape(var)}/,"")
          iostmt.register_io_var(:globals,var)
          code=sms_global_name(var)+subscript
          replace_element(code,:expr)
        else
          iostmt.register_io_var(:locals,var)
        end
      end
    end

  end

  # Generic classes

  class T < Treetop::Runtime::SyntaxNode

    def code_alloc_dealloc_globals(globals)
      code_alloc=[]
      code_dealloc=[]
      globals.sort.each do |var|
        varenv=varenv_get(var)
        d=(":"*varenv["dims"]).split("")
        t=varenv["type"]
        k=varenv["kind"]
        l=(t=="character")?("len(#{var})"):(nil)
        props={:attrs=>["allocatable"],:dims=>d,:kind=>k,:len=>l}
        declare(t,sms_global_name(var),props)
        dims=varenv["dims"]
        bounds_root=[]
        (1..dims).each do |i|
          bounds_root.push((decdim(varenv,i))?("#{fixbound(varenv,var,i,:l)}:#{fixbound(varenv,var,i,:u)}"):("lbound(#{var},#{i}):ubound(#{var},#{i})"))
        end
        bounds_root=bounds_root.join(",")
        bounds_nonroot=("1"*dims).split("").join(",")
        gvar=sms_global_name(var)
        svar=sms_statusvar
        code_alloc.push("if (#{sms_rootcheck}()) then")
        code_alloc.push("allocate(#{gvar}(#{bounds_root}),stat=#{svar})")
        code_alloc.push("else")
        code_alloc.push("allocate(#{gvar}(#{bounds_nonroot}),stat=#{svar})")
        code_alloc.push("endif")
        code_alloc.push(check_allocate(gvar,svar))
        code_dealloc.push("deallocate(#{gvar},stat=#{svar})")
        code_dealloc.push(check_deallocate(gvar,svar))
      end
      [code_alloc,code_dealloc]
    end

    def check_allocate(datavar,statusvar)
      check_op(statusvar,1,"Allocation of '#{datavar}' failed")
    end

    def check_deallocate(datavar,statusvar)
      check_op(statusvar,1,"Deallocation of '#{datavar}' failed")
    end

    def check_op(statusvar,retcode,msg)
      declare("integer",sms_rankvar)
      code=""
      code+="if (#{statusvar}.ne.0) then\n"
      code+="call sms__comm_rank(#{sms_rankvar})\n"
      code+="write (*,'(a,i0)') \"#{msg} on MPI rank \",#{sms_rankvar}\n"
      code+="#{sms_abort(retcode)}\n"
      code+="endif"
    end

    def code_bcast(vars,iostat=nil)
      code=[]
      vars.each do |var|
        varenv=varenv_get(var)
        sort=varenv["sort"]
        type=varenv["type"]
        if type=="character"
          arg2=(sort=="scalar")?("1"):("size(#{var})")
          code.push("if (#{iostat}.eq.0) then") if iostat
          code.push(sms_bcast_char(var,arg2))
          code.push(sms_abort_on_error)
          code.push("endif") if iostat
        else
          if sort=="scalar"
            dims="1"
            sizes="(/1/)"
          else
            dims=varenv["dims"]
            sizes="(/"+(1..dims.to_i).map { |r| "size(#{var},#{r})" }.join(",")+"/)"
          end
          kind=varenv["kind"]
          code.push("if (#{iostat}.eq.0) then") if iostat
          code.push(sms_bcast(var,sms_type(var),sizes,dims))
          code.push(sms_abort_on_error)
          code.push("endif") if iostat
        end
      end
      code
    end

    def code_decomp(dh,sort)
      unless sort==:array or sort==:scalar
        efail "sort must be :array or :scalar (was '#{sort}')"
      end
      dh=(dh)?("#{dh}(#{dh}__nestlevel)"):("sms__not_decomposed")
      dh="(/#{dh}/)" if sort==:array
      dh
    end

    def code_gather(vars)
      code=[]
      vars.each do |var|
        varenv=varenv_get(var)
        dh=varenv["decomp"]
        dims=varenv["dims"]
        type=code_type(var,varenv,:array)
        gllbs=code_global_lower_bounds(varenv,var,dims)
        glubs=code_global_upper_bounds(varenv,var,dims)
        gstrt=gllbs
        gstop=glubs
        perms=code_perms(varenv)
        decomp=code_decomp(dh,:array)
        args=[]
        args.push("#{maxrank}")
        args.push("1")
        args.push("#{gllbs}")
        args.push("#{glubs}")
        args.push("#{gstrt}")
        args.push("#{gstop}")
        args.push("#{perms}")
        args.push("#{decomp}")
        args.push("#{type}")
        args.push(".false.") # but why?
        args.push("#{var}")
        args.push(sms_global_name(var))
        args.push(sms_statusvar)
        code.push("call sms__gather(#{args.join(",")})")
        code.push(sms_abort_on_error)
      end
      code
    end

    def code_global_lower_bounds(varenv,var,dims)
      if dims
        "(/"+ranks.map { |r| (r>dims)?(1):(fixbound(varenv,var,r,:l)) }.join(",")+"/)"
      else
        "(/"+ranks.map { |r| 1 }.join(",")+"/)"
      end
    end

    def code_global_upper_bounds(varenv,var,dims)
      if dims
        "(/"+ranks.map { |r| (r>dims)?(1):(fixbound(varenv,var,r,:u)) }.join(",")+"/)"
      else
        "(/"+ranks.map { |r| 1 }.join(",")+"/)"
      end
    end

    def code_local_bound(dh,dd,lu)
      efail "lu must be :l or :u (was '#{lu}')" unless lu==:l or lu==:u
      "#{dh}__local_#{lu}b(#{dd},#{dh}__nestlevel)"
    end

    def code_perms(varenv)
      "(/"+ranks.map { |r| decdim(varenv,r)||0 }.join(",")+"/)"
    end

    def code_scatter(vars,iostat=nil)
      code=[]
      vars.each do |var|
        tag=sms_commtag
        varenv=varenv_get(var)
        dh=varenv["decomp"]
        ifail "No decomp defined" unless dh
        dims=varenv["dims"]
        type=code_type(var,varenv,:array)
        gllbs=code_global_lower_bounds(varenv,var,dims)
        glubs=code_global_upper_bounds(varenv,var,dims)
        gstrt=gllbs
        gstop=glubs
        halol="(/"+ranks.map { |r| (dd=decdim(varenv,r))?("#{dh}__halosize(#{dd},#{dh}__nestlevel)"):("0") }.join(",")+"/)"
        halou="(/"+ranks.map { |r| (dd=decdim(varenv,r))?("#{dh}__halosize(#{dd},#{dh}__nestlevel)"):("0") }.join(",")+"/)"
        perms=code_perms(varenv)
        decomp=code_decomp(dh,:array)
        args=[]
        args.push("#{maxrank}")
        args.push("1")
        args.push("#{tag}")
        args.push("#{gllbs}")
        args.push("#{glubs}")
        args.push("#{gstrt}")
        args.push("#{gstop}")
        args.push("#{perms}")
        args.push("#{halol}")
        args.push("#{halou}")
        args.push("#{decomp}")
        args.push("#{type}")
        args.push(sms_global_name(var))
        args.push("#{var}")
        args.push(sms_statusvar)
        stmt=""
        stmt+="if (#{iostat}.eq.0) " if iostat
        stmt+="call sms__scatter(#{args.join(",")})"
        code.push(stmt)
        code.push(sms_abort_on_error)
      end
      code
    end

    def code_type(var,varenv,sort)
      unless sort==:array or sort==:scalar
        efail "sort must be :array or :scalar (was '#{sort}')"
      end
      code=""
      code+="(/" if sort==:array
      code+=sms_type(var)
      code+="/)" if sort==:array
      code
    end

    def decdim(varenv,r)
      varenv["dim#{r}"]
    end

    def declare(type,var,props={})
      def mismatch(x,old,new)
        ifail "Upon redeclaration of '#{var}': old #{x}=#{old}, new #{x}=#{new}"
      end
      su=scoping_unit
      pppvars=(su.metadata[:pppvars]||={})
      varenv=varenv_get(var,su,false)
      if varenv
        ifail "#{var} is already declared" unless varenv["pppvar"]
        known=pppvars[var]
        ifail "#{var} not in scoping-unit metadata" unless known
        ktype=known[:type]
        mismatch("type",ktype,type) unless ktype==type
        kprops=known[:props]
        mismatch("props",kprops,props) unless kprops==props
      else
        pppvars[var]={:type=>type,:props=>props}
        lenopt=""
        if props[:len]
          unless type=="character"
            efail "'len' property incompatible with type '#{type}'"
          end
          lenopt="(len=#{props[:len]})"
        end
        kind=props[:kind]
        kind=([nil,"_"].include?(kind))?(""):("(kind=#{kind})")
        attrs=props[:attrs]||[]
        attrs=[attrs] unless attrs.is_a?(Array)
        attrs=(attrs.empty?)?(""):(",#{attrs.sort.join(",")}")
        code="#{type}#{kind}#{lenopt}#{attrs}::#{var}"
        dims=props[:dims]
        code+="(#{dims.join(',')})" if dims
        init=props[:init]
        code+="=#{init}" if init
        t=raw(code,:type_declaration_stmt,input.srcfile,input.dstfile,{:env=>env})
        newenv=t.input.envstack.last
        newenv[var]["pppvar"]=true
        dc=declaration_constructs
        t.parent=dc
        dc.e.push(t)
        node=self
        begin
          node.envref[var]=newenv[var] if node.respond_to?(:envref)
          break if node==su
          node=node.parent
        end while true
      end
      var
    end

    def distribute_array_bounds(spec_list,varenv)
      return unless spec_list
      return unless dh=varenv["decomp"]
      ok=[Assumed_Shape_Spec_List,Explicit_Shape_Spec_List,Implicit_Shape_Spec_List]
      return unless ok.include?(spec_list.class)
      newbounds=[]
      if spec_list.is_a?(Explicit_Shape_Spec_List)
        cb=spec_list.concrete_boundslist
        cb.each_index do |i|
          b=cb[i]
          arrdim=i+1
          if (dd=decdim(varenv,arrdim))
            use(sms_decompmod)
            s=code_local_bound(dh,dd,:l)+":"+code_local_bound(dh,dd,:u)
          else
            s=(b.clb=="1")?(b.cub):("#{b.clb}:#{b.cub}")
          end
          newbounds.push(s)
        end
      elsif spec_list.is_a?(Assumed_Shape_Spec_List) or spec_list.is_a?(Implicit_Shape_Spec_List)
        (1..varenv["dims"].to_i).each do |i|
          arrdim=i
          if (dd=decdim(varenv,arrdim)) and not varenv["lb#{arrdim}"]=="deferred"
            use(sms_decompmod)
            s=code_local_bound(dh,dd,:l)+":"
          else
            s=":"
          end
          newbounds.push(s)
        end
      end
      code=newbounds.join(",")
      replace_element(code,:array_spec,spec_list)
    end

    def fixbound(varenv,var,dim,x)
      bound=varenv["#{x}b#{dim}"]
      efail "Bad upper bound: #{bound}" if bound=="_" and x==:u
      return 1 if bound=="_" and x==:l
      if ["assumed","deferred","explicit"].include?(bound)
        if (dd=decdim(varenv,dim))
          dh=varenv["decomp"]
          lu=(x==:l)?("low"):("upper")
          return "#{dh}__#{lu}bounds(#{dd},#{dh}__nestlevel)"
        else
          return "#{x}bound(#{var},#{dim})"
        end
      end
      bound
    end

    def halo_offsets(dd)
      halo_lo=0
      halo_up=0
      if (halocomp=sms_halo_comp)
        offsets=halocomp.send("#{dd}")
        halo_lo=offsets.lo
        halo_up=offsets.up
      end
      OpenStruct.new({:lo=>"#{halo_lo}",:up=>"#{halo_up}"})
    end

    def intrinsic(function_name)
      intrinsics["#{function_name}"]
    end

    def known(var)
      varenv_get(var,self,expected=false)
    end

    def known_array(var)
      (varenv=known(var)) and varenv["sort"]=="array"
    end

    def known_distributed(var)
      (varenv=known(var)) and varenv["decomp"]
    end

    def known_pppvar(var)
      (varenv=known(var)) and varenv["pppvar"]
    end

    def known_scalar(var)
      (varenv=known(var)) and varenv["sort"]=="scalar"
    end

    def known_uservar(var)
      (varenv=known(var)) and not varenv["pppvar"]
    end

    def marker
      s=env[:global]
      s[:marker]||=0
      m=(s[:marker]+=1)
      f=File.basename(env[:global][:dstfile])
      "See \"marker #{m}\" in #{f}"
    end

    def maxrank
      7
    end

    def omp_parallel_loop(node=self)
      (opl=node.ancestor(OMP_Parallel_Do))?(opl):(nil)
    end

    def ranks
      (1..maxrank)
    end

    def sms(s)
      "#{e[0]}#{e[1]} #{s}\n"
    end

    def sms_abort(retcode,msg=nil)
      use(sms_decompmod)
      msg="#{marker}"+((msg)?(" [ #{msg} ]"):(""))
      "call sms__abort(#{retcode},'#{msg}')"
    end

    def sms_abort_on_error
      "if (#{sms_statusvar}.ne.0) #{sms_abort(1)}"
    end

    def sms_bcast(var,type,sizes,dims)
      "call sms__bcast(#{var},#{type},#{sizes},#{dims},#{sms_statusvar})"
    end

    def sms_bcast_char(var,arg2)
      "call sms__bcast_char(#{var},#{arg2},#{sms_statusvar})"
    end

    def sms_commtag
      s=env[:global]
      s[:tag]||=-1
      name="sms__tag_#{s[:tag]+=1}"
      declare("integer",name,{:attrs=>"save",:init=>"0"})
      name
    end

    def sms_decompmod
      "sms__decomp"
    end

    def sms_global_name(name)
      p="sms__global_"
      n="#{name}"
      maxnamelen=31
      tokeep=maxnamelen-p.size-1
      return "#{p}#{n}" if n.size<=tokeep
      @@global_names={} unless defined?(@@global_names)
      return @@global_names[n] if @@global_names[n]
      @@global_index=0 unless defined?(@@global_index)
      p="#{p}#{@@global_index+=1}_"
      tokeep=maxnamelen-p.size-1
      @@global_names[n]=p+n[0..tokeep]
    end

    def sms_maxvars
      25
    end

    def sms_parallel_loop(node=self)
      return node if node.is_a?(Do_Construct) and node.metadata[:parallel]
      while (node=node.ancestor(Do_Construct))
        return node if node.metadata[:parallel]
      end
      nil
    end

    def sms_rankvar
      "sms__rank"
    end

    def sms_rootcheck
      "sms__i_am_root"
    end

    def sms_serial_region(node=self)
      return node if node.is_a?(SMS_Serial)
      node.ancestor(SMS_Serial)
    end

    def sms_statusvar
      "sms__status"
    end

    def sms_stop(comm=nil)
      use(sms_decompmod)
      code=[]
      if comm
        code.push("call sms__stop(#{sms_statusvar},#{comm})")
      else
        code.push("call sms__stop(#{sms_statusvar})")
      end
      code.push(sms_abort_on_error)
      code.join("\n")
    end

    def sms_type(var)
      "sms__typeget(#{var})"
    end

  end # class T

  # Out-of-order class definitions (must be defined before subclassed)

  class SMS < NT
  end

  class SMS_Getter < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}")
    end

    def translate_with_options(description,function)
      # Check the sort and type of the indicated variable, if it exists in the
      # environment. If not, carry on and hope for the best.
      if (varenv=varenv_get(var,self,false))
        unless varenv["sort"]=="scalar" and varenv["type"]=="integer"
          efail "#{description} query's argument must be an integer scalar"
        end
      end
      code=[]
      code.push("#{self}")
      code.push("call #{function}(#{var})")
      replace_statement(code)
    end

    def var
      e[3]
    end

  end

  # Grammar-supporting subclasses

  class Allocate_Shape_Spec < NT

    def translate
      var="#{name}"
      varenv=varenv_get(var,self,false)
      if varenv and (dh=varenv["decomp"])
        use(sms_decompmod)
        arrdim=dim
        if (dd=decdim(varenv,arrdim))
          code=code_local_bound(dh,dd,:l)+":"+code_local_bound(dh,dd,:u)
          replace_element(code,:allocate_shape_spec)
        end
      end
    end

  end

  class Allocate_Stmt < Stmt

    def translate
      if sms_serial
        names.each { |name| sms_serial_info.allocated.add("#{name}") }
      end
    end

  end

  class Array_Name_And_Spec < NT

    def translate
      var="#{e[0]}"
      spec_list=e[2].spec_list
      varenv=varenv_get(var)
      distribute_array_bounds(spec_list,varenv)
    end

  end

  class Array_Section < NT
    include Array_Translation
  end

  class Array_Variable_Name < Variable_Name
    include Array_Translation
  end

  class Assign_Stmt < Stmt

    def translate
      if sms_serial
        variable=e[4]
        (sms_serial_info.lbl["#{variable}"]||=[]).push("#{self}")
        counter=sms_serial_info.lbl["#{variable}"].length
        replace_statement("#{self}; sms__label_assign_#{variable}=#{counter}")
      end
    end

  end

  class Close_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop or sms_serial
      io_stmt_init
      io_stmt_common
    end

  end

  class Deallocate_Stmt < Stmt

    def translate
      if sms_serial
        names.each { |name| sms_serial_info.deallocated.add("#{name}") }
      end
    end

  end

  class Do_Construct < NT

    def translate
      if metadata[:parallel]
        target=(opl=omp_parallel_loop)?(opl):(self)
        code=[]
        code.push("sms__parallel_depth=sms__parallel_depth+1")
        code.push(target)
        code.push("sms__parallel_depth=sms__parallel_depth-1")
        target.replace_statement(code)
      end
    end

  end

  class Do_Stmt < Stmt

    def do_stmt_translate
      return if sms_ignore or sms_serial
      if (p=sms_parallel)
        dh=p.decomp
        dd=nil
        [0,1,2].each do |i|
          if p.vars[i].include?("#{do_variable}")
            dd=i+1
            break
          end
        end
        if dd
          halo_lo=halo_offsets(dd).lo
          halo_up=halo_offsets(dd).up
          if loop_control.is_a?(Loop_Control_1)
            use(sms_decompmod)
            code="#{dh}__s#{dd}(#{loop_control.lb},#{halo_lo},#{dh}__nestlevel)"
            replace_element(code,:scalar_numeric_expr,loop_control.lb)
            code=",#{dh}__e#{dd}(#{loop_control.ub.value},#{halo_up},#{dh}__nestlevel)"
            replace_element(code,:loop_control_pair,loop_control.ub)
          elsif loop_control.is_a?(Loop_Control_2)
            ifail "Unexpected Loop_Control_2 node"
          end
        end
        if (h=sms_halo_comp)
          if "#{h.sidevar}"=="#{do_variable}"
            sms_sidevar="sms__#{do_variable}"
            varenv=varenv_get(do_variable)
            declare(varenv["type"],sms_sidevar)
            replace_element(sms_sidevar,:do_variable,do_variable)
            if loop_control.is_a?(Loop_Control_1)
              # The '!sms$parallel (dh,ipn) begin' directive, in current usage,
              # yields '[["ipn"], [], []]' for p.vars. The idea is to extract
              # 'ipn' as the iterator variable over grid points. In its full
              # glory, however, sms$parallel supports multipe iterator variable
              # names in each of the 1st, 2nd and 3rd decomposed dimensions. We
              # do the naive thing here: Expect the simplest possible usage, and
              # give up if we see something more complicated.
              errmsg="Unsupported sms$parallal / sms$halo_comp combination"
              pointvar_arrays=p.vars.reject { |x| x.empty? }
              ifail errmsg unless pointvar_arrays.size==1
              pointvar_array=pointvar_arrays.first
              ifail errmsg unless pointvar_array.size==1
              pointvar=pointvar_array.first
              # Now that we know the loop-over-points iterator variable name,
              # proceed with code modification.
              code=",#{dh}__nedge(#{pointvar})"
              replace_element(code,:loop_control_pair,loop_control.ub)
              code="#{h.sidevar}=#{dh}__permedge(#{sms_sidevar},#{pointvar})"
              sideloop=ancestor(Do_Construct)
              sideloop.body.e.unshift(raw(code,:assignment_stmt,input.srcfile,input.dstfile,{:env=>env}))
              use(sms_decompmod)
            elsif loop_control.is_a?(Loop_Control_2)
              ifail "Unexpected Loop_Control_2 node"
            end
          end
        end
      end
    end

  end

  class Entity_Decl_1 < Entity_Decl

    def translate
      var="#{name}"
      varenv=varenv_get(var)
      spec_list=nil
      if varenv["sort"]=="array"
        if (entity_decl_array_spec=e[1]).is_a?(Entity_Decl_Array_Spec)
          # entity_decl_array_spec case
          spec_list=entity_decl_array_spec.array_spec.spec_list
        else
          attr_spec_option=ancestor(Type_Declaration_Stmt).e[2]
          if attr_spec_option.is_a?(Attr_Spec_Option)
            if (d=attr_spec_option.dimension?)
              # dimension attribute case
              spec_list=d.spec_list
            end
          end
        end
      end
      distribute_array_bounds(spec_list,varenv)
    end

  end

  class Entry_Stmt < Stmt

    def translate
      nest_check("'entry' statement","sms$serial",sms_serial)
    end

  end

  class F2C_Continuation < NT
  end

  class F2C_Continuations < NT
  end

  class F2C_Directive < NT
  end

  class F2C_Initial < NT
  end

  class Flush_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop or sms_serial
      io_stmt_init
      io_stmt_common
    end

  end

  class If_Stmt < Stmt

    def translate
      code=[]
      code.push("#{sa(label)}#{prefix} then")
      code.push("#{action}")
      code.push("endif")
      replace_statement(code)
    end

  end

  class Io_Spec

    def pppvar_prefix
      "sms__io_"
    end

  end

  class Io_Spec_End < Io_Spec

    def pppvar
      declare("logical","#{pppvar_prefix}end")
    end

  end

  class Io_Spec_Eor < Io_Spec

    def pppvar
      declare("logical","#{pppvar_prefix}eor")
    end

  end

  class Io_Spec_Err < Io_Spec

    def pppvar
      declare("logical","#{pppvar_prefix}err")
    end

  end

  class Io_Stmt < NT

    def add_serial_region_nml_vars(serial_treatment)
      if (namelist_name=nml)
        nmlenv=varenv_get(namelist_name,self,expected=true)
        nmlenv["objects"].each do |x|
          if serial_treatment==:implicit_out
            varenv=varenv_get(x,self,expected=true)
            sms_serial_info.lvars.add(x)
            # A distributed-array lvar must be gathered to ensure that, if it
            # is not completely redefined in the serial region, scattering it
            # will restore existing values to the appropriate processors.
            sms_serial_info.rvars.add(x) if varenv["decomp"]
          elsif serial_treatment==:implicit_in
            sms_serial_info.rvars.add(x)
          else
            ifail "Serial region namelist variable not recognized."
          end
        end
      end
    end

    def io_stmt_bcasts
      # NB: Broadcasts for status variables (i.e. iostat et al) are handled in
      # io_stmt_var_set_logic.
      return if @var_bcast.empty?
      @need_decompmod=true unless @var_bcast.empty?
      @code_bcast.concat(code_bcast(@var_bcast,@iostat))
    end

    def io_stmt_branch_to_logic
      [
        :err,
        :end,
        :eor
      ].each do |x|
        # :err has precedence, per F90 9.4.1.6, 9.4.1.7
        if (spec=send(x))
          label_old,label_new=spec.send(:relabel)
          pppvar=spec.send(:pppvar)
          @spec_var_false.push("#{pppvar}=.false.")
          @spec_var_bcast.push(sms_bcast(pppvar,sms_type(pppvar),"(/1/)",1))
          @spec_var_bcast.push(sms_abort_on_error)
          @spec_var_true.push("#{label_new} #{pppvar}=.true.")
          @spec_var_goto.push("if (#{pppvar}) goto #{label_old}")
          @success_label=label_create unless @success_label
          @need_decompmod=true
        end
      end
    end

    def io_stmt_codegen
      use(sms_decompmod) if @need_decompmod
      code=[]
      io_ok_condition="#{sms_rootcheck}()"
      if @serialize_io
        if @code_gather.empty? and @code_scatter.empty?
          use(sms_decompmod)
          io_ok_condition+=".or.sms__parallel_depth.gt.0"
        end
        my_label=(label.empty?)?(nil):(label)
        my_label=label_delete if my_label
        code.push("#{my_label} continue") if my_label
      end
      code.concat(@code_alloc)
      code.concat(@code_gather)
      code.push("if (#{io_ok_condition}) then") if @serialize_io
      code.concat(@spec_var_false)
      code.push("#{self}".chomp)
      code.push("goto #{@success_label}") if @success_label
      code.concat(@spec_var_true)
      code.push("#{sa(@success_label)}endif") if @serialize_io
      code.concat(@spec_var_bcast)
      code.concat(@spec_var_goto)
      code.concat(@code_scatter)
      code.concat(@code_bcast)
      code.concat(@code_dealloc)
      replace_statement(code)
    end

    def io_stmt_common(treatment=nil)
      if treatment
        unless [:in,:out].include?(treatment)
          ifail "Treatment '#{treatment}' neither :in nor :out"
        end
        globals=metadata[:globals]||SortedSet.new
        @serialize_io=true unless globals.empty?
        globals.each do |global|
          ((treatment==:in)?(@var_gather):(@var_scatter)).add("#{global}")
        end
        if treatment==:out and (locals=metadata[:locals])
          locals.each do |local|
            @var_bcast.add(local) if @serialize_io
          end
        end
      end
      unless is_a?(Print_Stmt)
        io_stmt_branch_to_logic
        io_stmt_var_set_logic
      end
      declare("logical",sms_rootcheck) if @serialize_io
      @code_alloc,@code_dealloc=code_alloc_dealloc_globals(SortedSet.new(@var_gather+@var_scatter))
      io_stmt_gathers
      io_stmt_scatters
      io_stmt_bcasts
      io_stmt_codegen
    end

    def io_stmt_gathers
      @need_decompmod=true unless @var_gather.empty?
      @code_gather.concat(code_gather(@var_gather))
    end

    def io_stmt_init
      @code_bcast=[]
      @code_gather=[]
      @code_scatter=[]
      @iostat=nil
      @need_decompmod=false
      @serialize_io=true
      @spec_var_bcast=[]
      @spec_var_false=[]
      @spec_var_goto=[]
      @spec_var_true=[]
      @success_label=nil
      @var_bcast=SortedSet.new
      @var_gather=SortedSet.new
      @var_scatter=SortedSet.new
    end

    def io_stmt_scatters
      @need_decompmod=true unless @var_scatter.empty?
      @code_scatter.concat(code_scatter(@var_scatter,@iostat))
    end

    def io_stmt_var_set_logic
      [
        :access,
        :action,
        :blank,
        :delim,
        :direct,
        :exist,
        :form,
        :formatted,
        :iomsg,
        :iostat,
        :name,
        :named,
        :nextrec,
        :number,
        :opened,
        :pad,
        :position,
        :read,
        :readwrite,
        :recl,
        :sequential,
        :size,
        :unformatted,
        :write
      ].each do |x|
        if (spec=send(x))
          var=spec.rhs
          varenv=varenv_get(var)
          size=(varenv["type"]=="character")?("(/len(#{var})/)"):("(/1/)")
          @spec_var_bcast.push(sms_bcast(var,sms_type(var),size,1))
          @spec_var_bcast.push(sms_abort_on_error)
          @need_decompmod=true
          @iostat=var if x==:iostat
        end
      end
    end

    def register_io_var(key,value)
      (metadata[key]||=SortedSet.new).add(value)
    end

  end

  class Label_Do_Stmt < Do_Stmt

    def translate
      do_stmt_translate
    end

  end

  class Main_Program < Scoping_Unit

    def translate
      check_static
    end

  end

  class Module < Scoping_Unit

    def translate
      check_static
    end

  end

  class Name < T

    def globalize
      code=sms_global_name(self)
      replace_element(code,:name)
    end

    def name
      return @name if defined?(@name)
      @name="#{self}"
    end

    def size
      length
    end

    def translate

      def handle_serial

        def lvar?(varenv)
          return false if varenv["intent"]=="in"
          if inside?(Actual_Arg_Spec) # function(x,y,x) or call subroutrine(x,y,z)
            sms_serial_info.rvars.add(name)
            if (fn_stmt=ancestor(Function_Reference))
              fn_name=fn_stmt.e[0]
              return false if intrinsic(fn_name)
            end
            return true
          end
          return false if sms_serial_info.allocated.include?(name) # allocated in serial region
          return false if sms_serial_info.deallocated.include?(name) # deallocated in serial region
          return false if inside?(Section_Subscript_List) # array indexing
          return true  if inside?(Assignment_Stmt) and not inside?(Expr) # left side of assignment-stmt
          return true  if inside?(Io_Spec_Iostat,Allocate_Stat_Construct,Input_Item_List,Do_Variable)
          return true  if inside?(Data_Stmt_Object_List) and not inside?(Data_Implied_Do_Loop)
          return true  if inside?(Inquire_Spec_List) and not inside?(External_File_Unit,Inquire_Spec_File,Io_Spec_Err)
          false
        end

        def fail_if_allocate(varenv)
          if inside?(Allocate_Object)
            action=(inside?(Allocate_Stmt))?("allocated"):("deallocated")
            efail "Distributed array '#{name}' #{action} in serial region" if varenv["decomp"]
          end
        end

        unless inside?(SMS_Serial_Begin,Subroutine_Name,Function_Name) or intrinsic(name) or derived_type? or structure_component?
          varenv=varenv_get(name,self,expected=false)||{}
          fail_if_allocate(varenv)
          unless varenv["parameter"]
            if lvar?(varenv)
              sms_serial_info.lvars.add(name)
              # A distributed-array lvar must be gathered to ensure that, if it
              # is not completely redefined in the serial region, scattering it
              # will restore existing values to the appropriate processors.
              sms_serial_info.rvars.add(name) if varenv["decomp"]
            else
              # The following line used to end: unless varenv["intent"]=="out".
              # The (potential) problem: According to the Fortran standard, an
              # intent(out) variable's value becomes undefined upon routine
              # entry, so gathering it isn't reall defined. It may be ok in
              # practice, or it might not. We'll see. One workaround idea: Add,
              # as the first executable statement in the routine, a statement to
              # initialize the array with an appropriate value (i.e. not Lahey's
              # "bad" value).
              sms_serial_info.rvars.add(name)
            end
          end
        end

      end

      if (tolocal=sms_to_local) and (p=tolocal["#{name}"])
        case "#{p.key}"
        when "lbound"
          se="s#{p.dd}"
          halo_offset="#{halo_offsets(p.dd.to_s).lo}"
        when "ubound"
          se="e#{p.dd}"
          halo_offset="#{halo_offsets(p.dd.to_s).up}"
        else
          efail "Unrecognized sms$to_local key: #{p.key}"
        end
        code="#{p.dh}__#{se}(#{name},#{halo_offset},#{p.dh}__nestlevel)"
        replace_element(code,:expr)
      end

      handle_serial if sms_serial

    end

  end

  class Nonlabel_Do_Stmt < Do_Stmt

    def translate
      do_stmt_translate
    end

  end

  class Nullify_Stmt < Stmt

    def translate

      # See comment in Pointer_Assignment_Stmt#Translate.

      if sms_serial
        new_stmt=["#{self}"]
        si=sms_serial_info
        update=false
        vars=e[3].array
        vars.each do |pointer|
          p="#{pointer}"
          next if si.vars_ignore.include?(p)
          explicit_out=(si.vars_out.include?(p) or si.vars_inout.include?(p))
          implicit_in=(si.default==:in or si.default==:ignore)
          next if implicit_in and not explicit_out
          update=true
          (si.ptr[p]||=[]).push("nullify (#{p})")
          counter=si.ptr[p].length
          new_stmt.push("sms_ptr_assign_#{p}=#{counter}")
        end
        replace_statement(new_stmt) if update
      end
    end

  end

  class OMP_Directive < NT
  end

  class OMP_Parallel_Do < OMP_Directive
  end

  class OMP_Parallel_Do_Begin < NT

    def str0
      wrap("#{e[0]}#{e[1]}#{e[2]}#{e[3]}","!$omp")+"\n"
    end

  end

  class OMP_Parallel_Do_Body < NT
  end

  class OMP_Parallel_Do_End < OMP_Directive

    def str0
      wrap("#{e[0]}#{e[1]}#{e[2]}#{e[3]}","!$omp")+"\n"
    end

  end

  class Open_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop or sms_serial
      io_stmt_init
      io_stmt_common
    end

  end

  class Pointer_Assignment_Stmt < Stmt

    def translate

      # Do not replay assignment if pointer var is explicitly ignored, or if
      # default treatment is 'in' or 'ignore' and no explicit out treatment was
      # specified for the pointer var. Otherwise, arrange for replay of pointer
      # assignment on all tasks, after the serial region.

      if sms_serial
        p="#{e[1]}"
        si=sms_serial_info
        return if si.vars_ignore.include?(p)
        explicit_out=(si.vars_out.include?(p) or si.vars_inout.include?(p))
        implicit_in=(si.default==:in or si.default==:ignore)
        return if implicit_in and not explicit_out
        (si.ptr[p]||=[]).push("#{self}")
        counter=si.ptr[p].length
        replace_statement("#{self}; sms__ptr_assign_#{p}=#{counter}")
      end
    end

  end

  class Print_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop or sms_serial
      io_stmt_init
      io_stmt_common(:in)
    end

  end

  class Read_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop
      if sms_serial
        add_serial_region_nml_vars(:implicit_out)
      else
        io_stmt_init
        @serialize_io=false if unit.is_a?(Internal_File_Unit)
        if (namelist_name=nml)
          @serialize_io=true
          nmlenv=varenv_get(namelist_name,self,expected=true)
          nmlenv["objects"].each do |x|
            var=(x.respond_to?(:name))?("#{x.name}"):("#{x}")
            if (varenv=varenv_get(var,self,expected=false))
              if varenv["decomp"]
                @var_scatter.add(var)
                replace_input_item(x,sms_global_name(var))
              else
                @var_bcast.add(var)
              end
            end
          end
        end
        input_items.each do |x|
          var="#{x}"
          if known_scalar(var) and known_uservar(var)
            @var_bcast.add(var) if @serialize_io
          end
        end
        io_stmt_common(:out)
      end
    end

  end

  class Scoping_Unit < NT

    def check_static

      # Only for use with Main_Program & Module. Iterate over environment items,
      # skipping any whose keys are symbols (i.e. ppp metadata, not program
      # variables), are scalars or are not decomposed. If any explicit bounds
      # are found, exit with error. In the declaration sections of main programs
      # or modules, distributed arrays must be allocatable: Their translated
      # bounds contain references to non-static data structures that have no
      # compile-time values.

      env.each do |k,v|
        next if k.is_a?(Symbol) or not v["sort"]=="array" or not v["decomp"]
        (1..v["dims"].to_i).each do |dim|
          ["lb","ub"].each do |lub|
            if (b=v["#{lub}#{dim}"]) and b=="explicit"
              efail "Static distributed array ('#{k}') not supported"
            end
          end
        end
      end
    end

  end

  class SMS_Region < SMS
  end

  class SMS_Barrier < SMS

    def translate
      nest_check("sms$barrier","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$barrier","sms$parallel loop",sms_parallel_loop)
      use(sms_decompmod)
      code=[]
      code.push("#{self}")
      code.push("call sms__barrier(#{sms_statusvar})")
      code.push(sms_abort_on_error)
      replace_statement(code)
    end

  end

  class SMS_Comm_Rank < SMS_Getter

    def translate
      nest_check("sms$comm_rank","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$comm_rank","sms$parallel loop",sms_parallel_loop)
      translate_with_options("comm rank","sms__comm_rank")
    end

  end

  class SMS_Comm_Size < SMS_Getter

    def translate
      nest_check("sms$comm_size","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$comm_size","sms$parallel loop",sms_parallel_loop)
      translate_with_options("comm size","sms__comm_size")
    end

  end

  class SMS_Comment < SMS

    def str0
      ""
    end

  end

  class SMS_Compare_Var < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}")
    end

    def translate
      nest_check("sms$compare_var","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$compare_var","sms$parallel loop",sms_parallel_loop)
      use(sms_decompmod)
      declare("logical","sms__debugging_on")
      var="#{e[3].name}"
      varenv=varenv_get(var)
      dims=varenv["dims"]
      str="#{e[5]}"
      type=code_type(var,varenv,:scalar)
      gllbs=code_global_lower_bounds(varenv,var,dims)
      glubs=code_global_upper_bounds(varenv,var,dims)
      perms=code_perms(varenv)
      dh=code_decomp(varenv["decomp"],:scalar)
      dims||="1"
      code=[]
      code.push("#{self}")
      code.push("if (sms__debugging_on()) then")
      code.push("call sms__compare_var(#{dh},#{var},#{type},#{glubs},#{perms},#{gllbs},#{glubs},#{gllbs},#{dims},'#{var}',#{str},#{sms_statusvar})")
      code.push(sms_abort_on_error)
      code.push("endif")
      replace_statement(code)
    end

  end

  class SMS_Create_Decomp < SMS

    def decomp
      e[3]
    end

    def global
      e[5].vars
    end

    def halo
      e[7].vars
    end

    def regionsize
      e[8]
    end

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}#{e[7]}#{e[8]}#{e[9]}")
    end

    def translate
      nest_check("sms$create_decomp","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$create_decomp","sms$parallel loop",sms_parallel_loop)
      max=3
      d="#{decomp}"
      n="#{decomp}__nestlevel"
      use(sms_decompmod)
      declare("integer","sms__periodicusedlower",{:dims=>%W[sms__max_decomposed_dims]})
      declare("integer","sms__periodicusedupper",{:dims=>%W[sms__max_decomposed_dims]})
      code=[]
      code.push("#{self}")
      code.push("#{n}=1")
      code.push("#{d}__nregions=1")
      max.times do |i|
        dim=i+1
        g=global[i]
        h=halo[i]
        if g
          code.push("allocate(#{d}__s#{dim}(1:1,0:1,#{d}__maxnests))")
          code.push("allocate(#{d}__e#{dim}(#{g}:#{g},0:1,#{d}__maxnests))")
        end
        code.push("#{d}__globalsize(#{dim},#{n})=#{(g)?(g):(1)}")
        code.push("#{d}__localsize(#{dim},#{n})=0")
        code.push("#{d}__halosize(#{dim},#{n})=#{(h)?(h):(0)}")
        code.push("#{d}__boundarytype(#{dim})=sms__nonperiodic_bdy")
        code.push("#{d}__lowbounds(#{dim},#{n})=1")
      end
      max.times do |i|
        dim=i+1
        code.push("#{d}__upperbounds(#{dim},#{n})=#{d}__globalsize(#{dim},#{n})+#{d}__lowbounds(#{dim},#{n})-1")
      end
      max.times do |i|
        dim=i+1
        g=global[i]
        if g
          code.push("sms__periodicusedlower(:)=#{d}__lowbounds(:,#{dim})")
          code.push("sms__periodicusedupper(:)=#{d}__upperbounds(:,#{dim})")
        end
      end
      code.push("#{d}__decompname='#{d}'")
      args=[
        "sms__decomp_1",
        "#{d}__boundarytype",
        "#{d}__globalsize(1,#{n})",
        "#{d}__halosize(1,#{n})",
        "#{d}__lowbounds(1,#{n})",
        "sms__null_decomp",
        "#{d}__localsize(1,#{n})",
        "sms__periodicusedlower(1)",
        "sms__periodicusedupper(1)",
        code_local_bound(d,1,:l),
        code_local_bound(d,1,:u),
        "#{d}__decompname",
        "#{d}(#{n})",
        "sms__max_decomposed_dims",
        "sms__unstructured",
        "regionsize", # WHAT IS THIS?
        sms_statusvar
      ]
      code.push("call sms__create_decomp(#{args.join(',')})")
      code.push(sms_abort_on_error)
      code.push("do #{d}__index=0,0")
      args=[
        "#{d}(#{n})",
        "1",
        "#{d}__halosize(1,#{n})-#{d}__index",
        "#{d}__s1(1,#{d}__index,#{n})",
        "#{d}__e1(#{global[0]},#{d}__index,#{n})",
        "1",
        "1",
        "#{d}__nregions",
        sms_statusvar
      ]
      code.push("call sms__loops_op(#{args.join(',')})")
      code.push(sms_abort_on_error)
      code.push("end do")
      replace_statement(code)
    end

  end

  class SMS_Create_Decomp_Global < SMS

    def vars
      e[1].vars
    end

  end

  class SMS_Create_Decomp_Halo < SMS

    def vars
      e[1].vars
    end

  end

  class SMS_Create_Decomp_Regionsize < SMS

    def regionsize
      e[3]
    end

  end

  class SMS_Declare_Decomp < SMS

    def decomp
      e[3]
    end

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}#{e[7]}")
    end

    def translate
      if not inside?(Module) or inside?(Function_Subprogram,Subroutine_Subprogram)
        efail "sms$declare_decomp must appear in a module specification section"
      end
      use("sms__module")
      declare("integer","#{decomp}__maxnests",{:attrs=>"parameter",:init=>"1"})
      declare("integer","#{decomp}__ppp_max_regions",{:attrs=>"parameter",:init=>"1"})
      declare("character*32","#{decomp}__decompname")
      declare("integer","#{decomp}",{:dims=>%W[1]})
      declare("integer","#{decomp}__boundarytype",{:dims=>%W[sms__max_decomposed_dims]})
      declare("integer","#{decomp}__e1",{:attrs=>["allocatable"],:dims=>%W[: : :]})
      declare("integer","#{decomp}__globalsize",  {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__halosize",    {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__ignore")
      declare("integer","#{decomp}__index")
      declare("integer","#{decomp}__local_lb",    {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__local_ub",    {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__localhalosize")
      declare("integer","#{decomp}__localsize",   {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__lowbounds",   {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
      declare("integer","#{decomp}__nedge",{:attrs=>["allocatable"],:dims=>[":"]})
      declare("integer","#{decomp}__nestlevel")
      declare("integer","#{decomp}__nestlevels",  {:dims=>%W[#{decomp}__maxnests]})
      declare("integer","#{decomp}__nregions")
      declare("integer","#{decomp}__permedge",{:attrs=>["allocatable"],:dims=>[":",":"]})
      declare("integer","#{decomp}__s1",{:attrs=>["allocatable"],:dims=>%W[: : :]})
      declare("integer","#{decomp}__upperbounds", {:dims=>%W[sms__max_decomposed_dims #{decomp}__maxnests]})
    end

  end

  class SMS_Declare_Decomp_Unstructured_Option < SMS
  end

  class SMS_Decomp_Name < SMS
  end

  class SMS_Distribute < SMS_Region
  end

  class SMS_Distribute_Begin < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]} #{e[7]}")
    end

  end

  class SMS_Distribute_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Distribute_Dims_1 < SMS

    def dims
      ["#{e[0]}".to_i,"#{e[2]}".to_i]
    end

  end

  class SMS_Distribute_Dims_2 < SMS

    def dims
      [nil,"#{e[1]}".to_i]
    end

  end

  class SMS_Distribute_Dims_3 < SMS

    def dims
      ["#{e[0]}".to_i,nil]
    end

  end

  class SMS_Exchange_Common < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4].e.reduce("") { |m,x| m+="#{x.e[0]}#{x.e[1]}" }}#{e[5]}")
    end

    def translate_common(overlap)

      use(sms_decompmod)
      v=e[4].e.reduce([e[3]]) { |m,x| m.push(x.e[1]) }
      nvars=v.size
      maxnamelen=v.reduce(0) { |m,x| m=(x.name.length>m)?(x.name.length):(m) }
      code=[]

      code.push("#{self}")

      pre="sms__exchange_"
      gllbs="#{pre}gllbs"
      glubs="#{pre}glubs"
      strts="#{pre}gstrt"
      stops="#{pre}gstop"
      perms="#{pre}perms"
      types="#{pre}types"
      dcmps="#{pre}dcmps"
      names="#{pre}names"

      (nvars+1..25).each { |x| declare("integer","sms__x#{x}",{:dims=>%W[1],:init=>"0"}) }

      declare("integer",gllbs,{:dims=>%W[#{maxrank} #{sms_maxvars}]})
      declare("integer",glubs,{:dims=>%W[#{maxrank} #{sms_maxvars}]})
      declare("integer",strts,{:dims=>%W[#{maxrank} #{sms_maxvars}]})
      declare("integer",stops,{:dims=>%W[#{maxrank} #{sms_maxvars}]})
      declare("integer",perms,{:dims=>%W[#{maxrank} #{sms_maxvars}]})
      declare("integer",dcmps,{:dims=>%W[           #{sms_maxvars}]})
      declare("integer",types,{:dims=>%W[           #{sms_maxvars}]})

      declare("character(len=32)",names,{:dims=>%W[#{sms_maxvars}]})

      code.push("#{gllbs}= 1")
      code.push("#{glubs}= 1")
      code.push("#{strts}= 1")
      code.push("#{stops}= 1")
      code.push("#{perms}= 0")
      code.push("#{types}=-1")
      code.push("#{dcmps}=-1")
      code.push("#{names}=char(0)")

      (0..nvars-1).each do |i|
        this=v[i]

        # Derived types are not currently supported.

        if this.derived_type?
          efail "Derived type instance '#{this}' may not be exchanged"
        end

        arrdim=i+1
        var=this.name
        varenv=varenv_get(var)
        dims=varenv["dims"]
        efail "Scalar variable '#{var}' may not be exchanged" unless dims
        dh=varenv["decomp"]
        efail "Non-decomposed variable '#{var}' may not be exchanged" unless dh
        sl=this.subscript_list
        unless sl.empty?
          unless sl.size==dims.to_i
            efail "'#{this}' subscript list must be rank #{dims}"
          end
        end
        (1..dims).each do |r|
          x=sl[r-1]
          lower=(x and x.lower)?(x.lower):(fixbound(varenv,var,r,:l))
          upper=(x and x.upper)?(x.upper):(fixbound(varenv,var,r,:u))
          code.push("#{gllbs}(#{r},#{arrdim})=#{fixbound(varenv,var,r,:l)}")
          code.push("#{glubs}(#{r},#{arrdim})=#{fixbound(varenv,var,r,:u)}")
          code.push("#{strts}(#{r},#{arrdim})=#{lower}")
          code.push("#{stops}(#{r},#{arrdim})=#{upper}")
          code.push("#{perms}(#{r},#{arrdim})=1") if decdim(varenv,r)
        end
        code.push("#{dcmps}(#{arrdim})=#{dh}(#{dh}__nestlevel)")
        code.push("#{types}(#{arrdim})=#{sms_type(var)}")
        code.push("#{names}(#{arrdim})='#{var}'//char(0)")
      end

      tag=sms_commtag
      vars=(1..sms_maxvars).reduce([]) { |m,x| m.push((x>nvars)?("sms__x#{x}"):("#{v[x-1].name}")) }.join(",")
      code.push("call sms__exchange(#{nvars},#{tag},#{gllbs},#{glubs},#{strts},#{stops},#{perms},#{dcmps},#{types},#{names},#{sms_statusvar},#{overlap},#{vars})")
      code.push(sms_abort_on_error)
      replace_statement(code)

    end

  end

  class SMS_Exchange < SMS_Exchange_Common

    def translate
      nest_check("sms$exchange","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$exchange","sms$parallel loop",sms_parallel_loop)
      translate_common(".false.")
    end

  end

  class SMS_Exchange_Begin < SMS_Exchange_Common

    def translate
      nest_check("sms$exchange_begin","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$exchange_begin","sms$parallel loop",sms_parallel_loop)
      translate_common(".true.")
    end

  end

  class SMS_Exchange_End < SMS

    def str0
      sms("")
    end

    def translate
      nest_check("sms$exchange_end","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$exchange_end","sms$parallel loop",sms_parallel_loop)
      code=[]
      code.push("#{self}")
      code.push("call sms__exchange_end")
      replace_statement(code)
    end

  end

  class SMS_Executable_SMS_Halo_Comp < SMS
  end

  class SMS_Executable_SMS_Parallel < SMS
  end

  class SMS_Executable_SMS_Serial < SMS
  end

  class SMS_Executable_SMS_To_Local < SMS
  end

  class SMS_Get_Communicator < SMS_Getter

    def translate
      nest_check("sms$get_communicator","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$get_communicator","sms$parallel loop",sms_parallel_loop)
      translate_with_options("communicator","sms__get_communicator")
    end

  end

  class SMS_Halo_Comp < SMS_Region

    def str0
      "#{e[0]}#{e[1]}#{e[2]}"
    end

  end

  class SMS_Halo_Comp_Begin < SMS

    def sidevar
      (e[4].is_a?(SMS_Halo_Comp_Sidevar))?(e[4].sidevar):(nil)
    end

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]} #{e[6]}")
    end

  end

  class SMS_Halo_Comp_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Halo_Comp_Pair < SMS

    def lo
      e[1]
    end

    def up
      e[3]
    end

  end

  class SMS_Halo_Comp_Pairs < SMS

    def str0
      dim1="#{e[0]}"
      dim2=(e[1].e)?("#{e[1].e[1]}"):(nil)
      dim3=(e[2].e)?("#{e[2].e[1]}"):(nil)
      dims=[dim1,dim2,dim3]
      dims.delete_if { |x| x.nil? }
      dims.join(",")
    end

  end

  class SMS_Halo_Comp_Setup < SMS

    def decomp
      e[3]
    end

    def nedge
      e[5]
    end

    def permedge
      e[7]
    end

    def translate

      use(sms_decompmod)

      [[nedge,1],[permedge,2]].each do |var,rank|
        varenv=varenv_get(var)
        unless varenv["dims"]==rank
          efail "sms$halo_comp_setup variable '#{var}' must be rank #{rank}"
        end
        unless varenv["type"]=="integer"
          efail "sms$halo_comp_setup variable '#{var}' must be type integer"
        end
        unless varenv["sort"]=="array"
          efail "sms$halo_comp_setup variable '#{var}' must be an array"
        end
      end

      code=[]
      code.push("#{self}")
      code.push("allocate(#{decomp}__nedge(lbound(#{nedge},1):ubound(#{nedge},1)),stat=#{sms_statusvar})")
      code.push(check_allocate("#{decomp}__nedge",sms_statusvar))
      code.push("#{decomp}__nedge=#{nedge}")
      code.push("allocate(#{decomp}__permedge(lbound(#{permedge},1):ubound(#{permedge},1),lbound(#{permedge},2):ubound(#{permedge},2)),stat=#{sms_statusvar})")
      code.push(check_allocate("#{decomp}__permedge",sms_statusvar))
      code.push("#{decomp}__permedge=#{permedge}")
      replace_statement(code)

    end

  end

  class SMS_Halo_Comp_Sidevar_Option < NT

    def sidevar
      e[1]
    end

  end

  class SMS_Ignore < SMS_Region

    def translate
      nest_check("sms$ignore","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$ignore","sms$parallel loop",sms_parallel_loop)
    end

  end

  class SMS_Ignore_Begin < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Ignore_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Parallel < SMS_Region

    def decomp
      e[0].decomp
    end

    def str0
      "#{e[0]}#{e[1]}#{e[2]}"
    end

    def vars
      e[0].vars
    end

  end

  class SMS_Parallel_Begin < SMS

    def decomp
      e[3]
    end

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]} #{e[7]}")
    end

    def vars
      e[5].vars
    end

  end

  class SMS_Parallel_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Parallel_Var_List_1 < SMS

    def str0
      s="#{e[0]}#{e[1]}"
      s+=e[2].e.reduce("") { |m,x| m+="#{x.e[1]}" } if e[2].e
      s+="#{e[3]}"
    end

    def vars
      ["#{e[1]}"]+((e[2].e)?(e[2].e.reduce([]) { |m,x| m.push("#{x.e[1]}") }):([]))
    end

  end

  class SMS_Parallel_Var_List_2 < SMS

    def str0
      "#{e[0]}"
    end

    def vars
      ["#{e[0]}"]
    end

  end

  class SMS_Parallel_Var_Lists_001 < SMS

    def vars
      [[],[],e[2].vars]
    end

  end

  class SMS_Parallel_Var_Lists_010 < SMS

    def vars
      [[],e[1].vars,[]]
    end

  end

  class SMS_Parallel_Var_Lists_011 < SMS

    def vars
      [[],e[1].vars,e[3].vars]
    end

  end

  class SMS_Parallel_Var_Lists_100 < SMS

    def vars
      [e[0].vars,[],[]]
    end

  end

  class SMS_Parallel_Var_Lists_101 < SMS

    def vars
      [e[0].vars,[],e[3].vars]
    end

  end

  class SMS_Parallel_Var_Lists_110 < SMS

    def vars
      [e[0].vars,e[2].vars,[]]
    end

  end

  class SMS_Parallel_Var_Lists_111 < SMS

    def vars
      [e[0].vars,e[2].vars,e[4].vars]
    end

  end

  class SMS_Reduce < SMS

    def op
      e[5]
    end

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]}")
    end

    def translate
      nest_check("sms$reduce","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$reduce","sms$parallel loop",sms_parallel_loop)
      nvars=vars.size
      efail "sms$reduce supports reduction of #{sms_maxvars} variables max" if nvars>sms_maxvars
      use(sms_decompmod)
      sizes=[]
      types=[]
      nvars.times do |i|
        var=vars[i]
        varenv=varenv_get(var)
        efail "sms$reduce inapplicable to distributed array '#{var}'" if varenv["decomp"]
        sizes.push((varenv["sort"]=="array")?("size(#{var})"):("1"))
        types.push(sms_type(var))
      end
      sizes="(/#{sizes.join(",")}/)"
      types="(/#{types.join(",")}/)"
      code=[]
      code.push("#{self}")
      code.push("call sms__reduce_#{nvars}(#{sizes},#{types},sms__op_#{op},#{sms_statusvar},#{vars.join(',')})")
      code.push(sms_abort_on_error)
      replace_statement(code)
    end

    def vars
      e[3].vars
    end

  end

  class SMS_Reduce_Varlist < SMS

    def vars
      list_str.split(",")
    end

    def str0
      list_str
    end

  end

  class SMS_Serial < SMS_Region

    def not_in_env(name)
      efail "sms$serial-region variable '#{name}' not found in environment and not ignored"
    end

    def str0
      "#{e[0]}#{e[1]}#{e[2]}"
    end

    def translate

      nest_check("sms$serial","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$serial","sms$parallel loop",sms_parallel_loop)

      serial_begin=e[0]
      oldblock=e[1]
      efail "sms$serial region contains no statements" if oldblock.e.empty?
      serial_end=e[2]
      return if oldblock.e.empty?
      use(sms_decompmod)
      declare("logical",sms_rootcheck)

      # Initially, we don't know which variables will need to be broadcast,
      # gathered, or scattered.

      bcasts=[]
      gathers=[]
      scatters=[]

      # Globally-sized variables must be allocated/deallocated for distributed
      # arrays appearing within serial regions. Here's a set, initially empty,
      # to track them.

      globals=SortedSet.new

      # Get the serial info recorded when the serial_begin statement was parsed.

      si=sms_serial_info

      # Build up a set of variables present in serial-region statements and/or
      # mentioned in the in/inout/out clauses of the serial directive for
      # potential communication. Start with in/inout/out-clause variables.

      # Add explicit-treatment variables.

      commvars=SortedSet.new
      [:ignore,:in,:inout,:out].each do |treatment|
        if (vars=eval("si.vars_#{treatment}"))
          vars.each { |var| commvars.add([var,treatment]) }
        end
      end

      # Forbid multiple treatment.

      commvars.group_by { |var,treatment| var }.each do |k,v|
        if v.size>1
          t=v.map { |var,treatment| "'#{treatment}'" }.join(", ")
          efail "Multiple treatment (#{t}) specified for sms$serial variable '#{k}'"
        end
      end

      # Merge in variables found in serial-region statements and specify their
      # control.

      [[si.lvars,:implicit_out],[si.rvars,:implicit_in]].each do |vars,treatment|
        vars.each { |var| commvars.add([var,treatment]) }
      end

      # Reject all but the highest-priority treatment for each variable. At this
      # point, variables found both in serial-region statements and found in the
      # serial region will have multiple treatment but those for which explicit
      # treatment was specified will take precedence.

      priority={:ignore=>3,:inout=>2,:in=>1,:out=>1,:implicit_in=>0,:implicit_out=>0}
      commvars.group_by { |var,treatment| var }.each do |k,v|
        top=priority[v.max_by { |var,treatment| priority[treatment] }.last]
        commvars.reject! { |var,treatment| var==k and priority[treatment]<top }
      end

      # Apply default treatment if necessary, and ensure that variables needing
      # communication are known in the environment. Handle out-of-environment
      # variables in specification and derived types that are not ignored.

      commvars.each do |var_treatment|
        var,treatment=var_treatment
        default=si.default
        varenv=varenv_get(var,self,false)||{}
        if treatment==:implicit_in or treatment==:implicit_out
          unless default==:ignore or default==:unspecified
            not_in_env(var) if varenv.empty?
            efail "Derived type '#{var}' cannot be communicated in sms$serial region" unless basetype_chk(varenv["type"])
          end
          dh=(varenv)?(varenv["decomp"]):(nil)
          var_treatment[1]=case default
                           when :ignore
                             :ignore
                           when :inout
                             (dh)?(:inout):(:out)
                           when :in
                             (dh)?(:in):(:ignore)
                           when :out
                             :out
                           when :unspecified
                             case treatment
                             when :implicit_out
                               :implicit_out
                             when :implicit_in
                               (dh)?(:implicit_in):(:ignore)
                             end
                           else
                             efail "Unknown sms$serial default treatment '#{default}'"
                           end
        else
          unless treatment==:ignore or varenv.empty?
            efail "Derived type '#{var}' cannot be communicated in sms$serial region" unless basetype_chk(varenv["type"])
          end
        end
      end

      # Refresh the sorted set to eliminate duplicates created from applying
      # the same default treatment to previously different :implicit_in and
      # :implicit_out serial-region variables.

      commvars=SortedSet.new(commvars)

      # Schedule necessary communication of serial-region variables.

      def schedule_in(var,gathers)
        gathers.push(var)
      end

      def schedule_out(var,sort,dh,bcasts,scatters)
        ((sort=="scalar"||!dh)?(bcasts):(scatters)).push(var)
      end

      commvars.each do |var,treatment|
        expected=([:ignore,:implicit_in,:implicit_out].include?(treatment))?(false):(true)
        varenv=varenv_get(var,self,expected)
        dh=(varenv)?(varenv["decomp"]):(nil)
        sort=(varenv)?(varenv["sort"]):(nil)
        next if sort=="namelist"
        globals.add(var) if dh
        if varenv and basetype_chk(varenv["type"])
          case treatment
          when :ignore
          when :in
            efail "sms$serial 'in' variable '#{var}' is not decomposed" unless dh
            schedule_in(var,gathers)
          when :inout
            efail "sms$serial 'inout' variable '#{var}' is not decomposed" unless dh
            schedule_in(var,gathers)
            schedule_out(var,sort,dh,bcasts,scatters)
          when :out
            schedule_out(var,sort,dh,bcasts,scatters)
          when :implicit_in
            schedule_in(var,gathers)
          when :implicit_out
            schedule_out(var,sort,dh,bcasts,scatters)
          else
            ifail "Unknown sms$serial treatment '#{treatment}'"
          end
        end
      end

      # Walk the subtree representing the serial region's body and replace the
      # names of all scattered/gathered variables with their global versions.

      def globalize(node,to_globalize)
        node.e.each { |x| globalize(x,to_globalize) } if node.e
        node.globalize if node.is_a?(Name) and to_globalize.include?("#{node}")
      end
      globalize(oldblock,globals)

      # Declare globally-sized variables

      globals.sort.each do |var|
        varenv=varenv_get(var)
        dims=(":"*varenv["dims"]).split("")
        kind=varenv["kind"]
        type=varenv["type"]
        len=(type=="character")?("len(#{var})"):(nil)
        props={:attrs=>["allocatable"],:dims=>dims,:kind=>kind,:len=>len}
        declare(type,sms_global_name(var),props)
      end

      restates=[]

      # Declare and broadcast sms-created variables that handle pointers,
      # and assign-statements. Add logic based on runtime behavior that will
      # execute these statements correctly on all nodes.

      [:lbl,:ptr].each do |type|
        list=eval("si.#{type}").sort
        list.each do |var,info|
          sms_var="sms__#{type}_assign_#{var}"
          declare("integer",sms_var)
          bcasts.push(sms_var) unless bcasts.include?(sms_var)
          restates.push("select case (#{sms_var})")
          info.each_index do |idx|
            restates.push("case (#{idx+1})")
            restates.push(info[idx])
          end
          restates.push("case default")
          restates.push(sms_abort(1,"RUNTIME ERROR: '#{var}' #{type} assign case construct has no matching statement"))
          restates.push("end select")
        end
      end

      code1=[]
      code2=[]

      # Collect code for allocation and deallocation of globals.

      code_alloc,code_dealloc=code_alloc_dealloc_globals(globals)

      # Concatenate code.

      code1.concat(code_alloc)
      code1.concat(code_gather(gathers))
      code1.push("continue")
      code1.concat(code_scatter(scatters))
      code1.concat(code_bcast(bcasts))
      code1.concat(code_dealloc)
      code1.push(restates)

      code2.push("if (#{sms_rootcheck}()) then")
      code2.push("sms__serial_depth=sms__serial_depth+1")
      code2.push("continue")
      code2.push("sms__serial_depth=sms__serial_depth-1")
      code2.push("endif")

      # Replace serial region with new code block.

      env[:sms_serial]=false
      replace_statement_serial_opt([code1,code2],e)

    end

  end

  class SMS_Serial_Begin < SMS

    def control
      (c=e[2].is_a?(SMS_Serial_Control))?(e[2]):(nil)
    end

    def str0
      sms("#{sa(e[2])}#{e[3]}")
    end

    def translate
      si=(sms_serial_info=OpenStruct.new)
      si.allocated=Set.new
      si.deallocated=Set.new
      si.lvars=Set.new
      si.rvars=Set.new
      si.ptr=Hash.new()
      si.lbl=Hash.new()
      si.default     = control ? "#{control.default}".to_sym : :unspecified
      si.vars_ignore = control ? control.vars_ignore         : []
      si.vars_in     = control ? control.vars_in             : []
      si.vars_inout  = control ? control.vars_inout          : []
      si.vars_out    = control ? control.vars_out            : []
      parent.env[:sms_serial_info]=sms_serial_info
    end

  end

  class SMS_Serial_Control < SMS

    def control
      e[1]
    end

    def default
      control.default
    end

    def vars_ignore
      control.vars_ignore
    end

    def vars_in
      control.vars_in
    end

    def vars_inout
      control.vars_inout
    end

    def vars_out
      control.vars_out
    end

  end

  class SMS_Serial_Control_Option_1 < SMS

    def default
      (e[1].e&&e[1].e[1].respond_to?(:treatment))?(e[1].e[1].treatment):(:unspecified)
    end

    def sms_serial_treatment_lists
      e[0]
    end

    def str0
      s="#{e[0]}"
      s+="#{e[1].e[0]}#{e[1].e[1]}" if e[1].e
      s
    end

    def vars_ignore
      sms_serial_treatment_lists.vars_ignore
    end

    def vars_in
      sms_serial_treatment_lists.vars_in
    end

    def vars_inout
      sms_serial_treatment_lists.vars_inout
    end

    def vars_out
      sms_serial_treatment_lists.vars_out
    end

  end

  class SMS_Serial_Control_Option_2 < SMS

    def default
      e[0].treatment
    end

    def vars_ignore
      []
    end

    def vars_in
      []
    end

    def vars_inout
      []
    end

    def vars_out
      []
    end

  end

  class SMS_Serial_Default < SMS

    def treatment
      e[2]
    end

  end

  class SMS_Serial_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_Serial_Treatment_List < SMS

    def treatment
      e[3]
    end

    def vars
      e[1].vars
    end

  end

  class SMS_Serial_Treatment_Lists < SMS

    def vars_with_treatment(treatment)
      vars=("#{e[0].treatment}"=="#{treatment}")?(e[0].vars):([])
      e[1].e.each { |x| vars+=x.e[1].vars if "#{x.e[1].treatment}"=="#{treatment}" }
      vars
    end

    def str0
      "#{e[0]}"+e[1].e.reduce("") { |m,x| m+"#{x.e[0]}#{x.e[1]}" }
    end

    def vars_ignore
      vars_with_treatment(:ignore)
    end

    def vars_in
      vars_with_treatment(:in)
    end

    def vars_inout
      vars_with_treatment(:inout)
    end

    def vars_out
      vars_with_treatment(:out)
    end

  end

  class SMS_Serial_Varlist < SMS

    def str0
      list_str
    end

    def vars
      list_str.split(",")
    end

  end

  class SMS_Set_Communicator < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}")
    end

    def translate
      nest_check("sms$set_communicator","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$set_communicator","sms$parallel loop",sms_parallel_loop)
      use(sms_decompmod)
      code=[]
      code.push("#{self}")
      code.push("call sms__set_communicator(#{e[3]},#{sms_statusvar})")
      code.push(sms_abort_on_error)
      replace_statement(code)
    end

  end

  class SMS_Start < SMS

    def translate
      nest_check("sms$start","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$start","sms$parallel loop",sms_parallel_loop)
      use(sms_decompmod)
      code=[]
      code.push("#{self}")
      code.push("call sms__start(#{sms_statusvar})")
      code.push(sms_abort_on_error)
      replace_statement(code)
    end

  end

  class SMS_Stop < SMS

    def comm
      (e[2].is_a?(SMS_Stop_Option))?(e[2].comm):(nil)
    end

    def translate
      nest_check("sms$stop","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$stop","sms$parallel loop",sms_parallel_loop)
      code=[]
      code.push("#{self}")
      code.push(sms_stop(comm))
      replace_statement(code)
    end

  end

  class SMS_Stop_Option < SMS

    def comm
      e[1]
    end

  end

  class SMS_To_Local < SMS_Region

    def str0
      "#{e[0]}#{e[1]}#{e[2]}"
    end

    def translate
      nest_check("sms$to_local","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$to_local","sms$parallel loop",sms_parallel_loop)
    end

  end

  class SMS_To_Local_Begin < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}#{e[5]}#{e[6]} #{e[7]}")
    end

  end

  class SMS_To_Local_End < SMS

    def str0
      sms("#{e[2]}")
    end

  end

  class SMS_To_Local_List < SMS

    def dd
      e[1]
    end

    def key
      e[5]
    end

    def idx
      "#{dd}".to_i
    end

    def vars
      e[3].vars
    end

  end

  class SMS_To_Local_Lists < SMS

    def str0
      s="#{e[0]}"
      if p=e[1].e
        s+="#{p[0]}#{p[1]}"
        if p=p[2].e
          s+="#{p[0]}#{p[1]}"
        end
      end
      s
    end

    def vars
      def rec(list,v)
        list.vars.each do |x|
          v[x]=OpenStruct.new({:dd=>list.idx,:key=>"#{list.key}"})
        end
      end
      v={}
      rec(e[0],v)
      if p=e[1].e
        rec(p[1],v)
        rec(p[1],v) if p=p[2].e
      end
      v
    end

  end

  class SMS_Var_List < SMS

    def str0
      v=["#{e[0]}"]
      e[1].e.reduce(v) { |m,x| m.push("#{x.e[1]}") } if e[1].e
      v.join(",")
    end

    def vars
      ["#{e[0]}"]+((e[1].e)?(e[1].e.reduce([]) { |m,x| m.push("#{x.e[1]}") }):([]))
    end

  end

  class SMS_Unstructured_Grid < SMS

    def str0
      sms("#{e[2]}#{e[3]}#{e[4]}")
    end

    def translate
      nest_check("sms$unstructured_grid","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$unstructured_grid","sms$parallel loop",sms_parallel_loop)
      var="#{e[3]}"
      efail "No module info found for variable '#{var}'" unless (varenv=varenv_get(var))
      efail "No decomp info found for variable '#{var}'" unless (dh=varenv["decomp"])
      use(sms_decompmod)
      code=[]
      code.push("#{self}")
      code.push("call sms__unstructuredgrid(#{dh},size(#{var},1),#{var})")
      code.push("call sms__get_collapsed_halo_size(#{dh}(#{dh}__nestlevel),1,1,#{dh}__localhalosize,#{sms_statusvar})")
      code.push(sms_abort_on_error)
      code.push("#{dh}__s1(1,1,#{dh}__nestlevel)=#{dh}__s1(1,0,#{dh}__nestlevel)")
      code.push("#{dh}__e1(#{dh}__globalsize(1,#{dh}__nestlevel),1,#{dh}__nestlevel)=#{dh}__e1(#{dh}__globalsize(1,#{dh}__nestlevel),0,#{dh}__nestlevel)+#{dh}__localhalosize")
      replace_statement(code)
    end

  end

  class SMS_Unstructured_Print_Timers < SMS

    def translate
      nest_check("sms$unstructured_print_timers","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$unstructured_print_timers","sms$parallel loop",sms_parallel_loop)
      code=[]
      code.push("#{self}")
      code.push("call sms__unstructured_print_timers")
      replace_statement(code)
    end

  end

  class SMS_Varlist3D_1 < SMS

    def vars
      [e[0],e[2],e[4]]
    end

  end

  class SMS_Varlist3D_2 < SMS

    def vars
      [e[1],e[3]]
    end

  end

  class SMS_Varlist3D_3 < SMS

    def vars
      [e[2]]
    end

  end

  class SMS_Varlist3D_4 < SMS

    def vars
      [e[0],e[2]]
    end

  end

  class SMS_Varlist3D_5 < SMS

    def vars
      [e[1]]
    end

  end

  class SMS_Varlist3D_6 < SMS
    def vars
      [e[0]]
    end

  end

  class SMS_Zerotimers < SMS

    def translate
      nest_check("sms$zerotimers","$omp parallel loop",omp_parallel_loop)
      nest_check("sms$zerotimers","sms$parallel loop",sms_parallel_loop)
      code=[]
      code.push("#{self}")
      code.push("call sms__zerotimers")
      replace_statement(code)
    end

  end

  class Specification_Part < NT

    def translate
      if (vars=env[:vars])
        env[:vars].each do |var|
          varenv=env[var]
          # Forbid 'parameter' atrribute on distributed arrays.
          if varenv["decomp"] and varenv["parameter"]
            fail "Distributed array '#{var}' may not have the 'parameter' attribute"
          end
        end
      end
    end

  end

  class Stmt_Label < NT

    def errmsg_parallel(in_parallel_loop)
      io=(in_parallel_loop)?("out"):("in")
      "Branch to statement labeled '#{self}' from #{io}side parallel loop"
    end

    def errmsg_serial(in_serial_region)
      io=(in_serial_region)?("out"):("in")
      "Branch to statement labeled '#{self}' from #{io}side serial region"
    end

    def translate
      my_serial_region=sms_serial_region
      my_parallel_loop=sms_parallel_loop
      # Handle branches via numeric labels.
      if (bt=env[:branch_targets])
        (bt["#{self}"]||[]).each do |label|
          unless sms_serial_region(label)==my_serial_region
            efail errmsg_serial(my_serial_region)
          end
          unless sms_parallel_loop(label)==my_parallel_loop
            efail errmsg_parallel(my_parallel_loop)
          end
        end
      end
      # Handle branches via assigned goto statements.
      agt=env[:assigned_goto_targets]
      if (am=env[:assign_map])
        (am["#{self}"]||[]).each do |var|
          if (targets=agt[var])
            targets.each do |target|
              unless sms_serial_region(target)==my_serial_region
                fail errmsg_serial(my_serial_region)
              end
            end
          end
        end
      end
    end

  end

  class Stop_Stmt < Stmt

    def translate
      return if sms_ignore
      l=label_delete unless (l=label).empty?
      retcode=(stop_code and stop_code.numeric?)?("#{stop_code}"):("0")
      msg=(stop_code and stop_code.character?)?("#{stop_code}"):(nil)
      msg=msg.sub(/^['"]/,"").sub(/['"]$/,"") if msg
      code=[]
      code.push(sms_abort(retcode,msg))
      replace_statement(code)
    end

  end

  class Write_Stmt < Io_Stmt

    def translate
      return if omp_parallel_loop or sms_ignore or sms_parallel_loop
      if sms_serial
        add_serial_region_nml_vars(:implicit_in)
      else
        io_stmt_init
        function=(env["#{unit}"] and env["#{unit}"]["subprogram"]=="function")
        @serialize_io=false if unit.is_a?(Internal_File_Unit) or function
        if (namelist_name=nml)
          @serialize_io=true
          nmlenv=varenv_get(namelist_name,self,expected=true)
          nmlenv["objects"].each do |x|
            var=(x.respond_to?(:name))?("#{x.name}"):("#{x}")
            varenv=varenv_get(var,self,expected=true)
            if varenv["decomp"]
              @var_gather.add(var)
              replace_input_item(x,sms_global_name(var))
            end
          end
        end
        io_stmt_common(:in)
      end
    end

  end

end # module Fortran

class Driver


  def prepsrc_common(s,sms,omp)

    # Process SMS continuations, inserts and removes

    s=s.gsub(/^(#{sms}.*)&\s*\n#{sms}&(.*)/im,'\1\2')
    s=s.gsub(/^\s*#{sms}insert\s*/i,"")
    s=s.gsub(/^\s*#{sms}remove\s+begin.*?#{sms}remove\s+end/im,"")

    # Join OpenMP (END) PARALLEL DO directives

    a=s.split("\n")
    a.each_index do |i|
      s0=a[i].chomp
      j=i
      while s0=~/^#{omp}.*&$/i
        j+=1
        s0=(s0.sub(/\s*&$/i,'')+a[j].chomp.sub(/^\s*#{omp}(&)?\s*/i,'')).gsub(/\s+/,' ')
      end
      if s0=~/^\s*#{omp}\s*(end\s*)?parallel\s*do.*$/i
        a[i]=s0.downcase
        (j-i).times { a.delete_at(i+1) }
      end
    end
    s=a.join("\n")

    s

  end

  def prepsrc_fixed(s)
    prepsrc_common(s,'[c!\*]sms\$','[c!\*]\$omp')
  end

  def prepsrc_free(s)
    prepsrc_common(s,'!sms\$','!\$omp')
  end

end
