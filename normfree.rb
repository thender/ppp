module Normfree

  class Text < Treetop::Runtime::SyntaxNode
    def to_s
      elements.reduce("") { |s,e| s+="#{e}" }
    end
  end

  class Delete < Treetop::Runtime::SyntaxNode
    def to_s
      ""
    end
  end

  class Directive < Treetop::Runtime::SyntaxNode
    def to_s
      t=text_value
      t="\n"+t
    end
  end

  class Normalize < Treetop::Runtime::SyntaxNode
    def to_s
      t=text_value
      # Join continuation lines
      t=t.gsub(/&$(\n&?)?/,"")
      # Split semicolon-delimited statement lines
      t=t.gsub(/\s*;\s*/,"\n")
      # Attempting a multiline match of the regular expression below on a string
      # representing a huge source file is incredibly slow. Breaking the string
      # into lines improves performance significantly. 
      a=t.split("\n")
      a.each_index do |i|
        l=a[i]
        # Convert instances of F90:1016 char-string-edit-desc to quoted strings
        # to preserve case and whitespace.
        h=false
        p="\(.*?[0-9]{1,5}[ \t]format[ \t]*\\(.*?\)\([0-9]+\)[ \t]*[hH]\(.*?\)\\)\(.*\)"
        r=Regexp.new(p,true)
        while m=r.match(l)
          h=true
          p1=m[3][0..m[2].to_i-1]
          p2=m[3].sub(/^#{p1}/,"")
          l="#{m[1]}'#{p1}'#{p2})#{m[4]}"
        end
        # If a F90:1016 conversion occurred, quoted strings have been introduced
        # and it is no longer safe to change case or whitespace. Note, though,
        # that these conversions can only happen in the first normalization pass,
        # so that the second pass can normalize case and whitespace.
        unless h
          # Make upper-case characters lower-case
          l=l.downcase
          # Remove tabs & spaces
          l=l.gsub(/[ \t]+/,"")
        end
        a[i]=l
      end
      t=a.join("\n")
      # Remove blank lines
      t=t.gsub(/\n\n+/,"\n")
    end
  end

  class Quoted < Treetop::Runtime::SyntaxNode
    def to_s
      t=text_value
      t=t.gsub(/^!.*/,"")    # no comment lines
      t=t.gsub(/\n\n+/,"\n") # no blank lines
      t=t.gsub(/&$\n&?/,"")  # join continuation lines
    end
  end

end

# paul.a.madden@noaa.gov