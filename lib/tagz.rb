# -*- encoding : utf-8 -*-
unless defined? Tagz

# core tagz functions
#
  module Tagz
    require 'cgi'

    def Tagz.version()
      '10.0.0'
    end

    def Tagz.description
      <<-____

        tagz.rb is generates html, xml, or any sgml variant like a small ninja
        running across the backs of a herd of giraffes swatting of heads like
        a mark-up weedwacker.  weighing in at less than 300 lines of code
        tagz.rb adds an html/xml/sgml syntax to ruby that is both unobtrusive,
        safe, and available globally to objects without the need for any
        builder or superfluous objects.  tagz.rb is designed for applications
        that generate html to be able to do so easily in any context without
        heavyweight syntax or scoping issues, like a ninja sword through
        butter.

      ____
    end

  private
    # access tagz doc and enclose tagz operations
    #
      def tagz(*argv, &block)
        @tagz ||= nil ## shut wornings up
        previous = @tagz

        xmlns = nil
        options = argv.last.is_a?(Hash) ? argv.pop : {}
        document = argv.first
        options.each do |key, value|
          case key.to_s
          when "xmlns"
            xmlns = value
          when "tagz_reset"
            if value
              @tagz = nil
              previous = @tagz
            end
          else
            raise ArgumentError.new("unsupported option '#{key}'")
          end
        end

        if block
          @tagz ||= (Tagz.document.for(document) || Tagz.document.new)
          @tagz.using_namespace(xmlns) if xmlns
          begin
            previous_size = @tagz.size

            content = instance_eval(&block)

            current_size = @tagz.size

            content_was_added = current_size > previous_size

            unless content_was_added
              @tagz << content
            end

            @tagz
          ensure
            @tagz.reset_namespace if xmlns
            @tagz = previous
          end
        else
          document ? Tagz.document.for(document) : @tagz
        end
      end


    # open_tag
    #
      def tagz__(name, *argv, &block)
        options = argv.last.is_a?(Hash) ? argv.pop : {}
        content = argv

        # Fix for existing bug if the root element has dashes
        # and this method is called without the #tagz wrapper
        @tagz ||= Tagz.document.new

        attributes = Tagz.process_attributes(options) do |k,v|
          if k =~ /^xmlns:?(.*)/
            rp = tagz.get_prefix(v)
            unless ("" == $1 && :default == rp) \
                || $1 == tagz.get_prefix(v)
              tagz.reset_namespace($1, v)
              tagz.using_namespace(v, true)
            end
          end
        end

        tagz.using_namespace if tagz.prefix
        tagz.push "<#{ tagz.node(name) }#{ attributes }>"

        if content.empty?
          if block
            size = tagz.size
            value = block.arity.abs >= 1 ? block.call(tagz) : block.call()
            tagz.reset_namespace if tagz.prefix

            if value.nil?
              unless(tagz.size > size)
                tagz[-1] = "/>"
              else
                tagz.push "</#{ tagz.node(name) }>"
              end
            else
              tagz << value.to_s unless(tagz.size > size)
              tagz.push "</#{ tagz.node(name) }>"
            end
          end
        else
          tagz << content.join
          if block
            size = tagz.size

            value = block.arity.abs >= 1 ? block.call(tagz) : block.call()
            tagz << value.to_s unless(tagz.size > size)
          end
          tagz.reset_namespace if tagz.prefix
          tagz.push "</#{ tagz.node(name) }>"
        end

        tagz
      end

    # close_tag
    #
      def __tagz(tag, *a, &b)
        tagz.reset_namespace if tagz.prefix
        tagz.push "</#{ tagz.node(tag) }>"
        tagz
      end

    # processing instruction
    #

    def tagz_? name, *argv
      options = argv.last.is_a?(Hash) ? argv.pop : {}
      attributes = Tagz.process_attributes options
      tagz.write "<?#{ name }#{ attributes }?>"
    end

    # allow initial registration of namespaces

      def tagz_register_namespace(prefix, nsuri)
        @tagz ||= Tagz.document.new
        tagz.register_namespace(prefix, nsuri)
      end

      def tagz_register_default_namespace(nsuri)
        tagz_register_namespace(:default, nsuri)
      end

    # catch special tagz methods
    #
      def method_missing(m, *a, &b)
        strategy =
          case m.to_s
            when %r/^(.*[^?])_\?$/o
              :processing_instruction
            when %r/^(.*[^_])_(!)?$/o
              :open_tag
            when %r/^_([^_].*)$/o
              :close_tag
            when 'e'
              :element
            when '__', '___'
              :puts
            else
              nil
          end

        if(strategy.nil? or (tagz.nil? and Tagz.privately===self))
          begin
            return super
          ensure
            $!.set_backtrace caller(1) if $!
          end
        end
        
        case strategy
          when :open_tag
            m, bang = $1, $2
            b ||= lambda{} if bang
            tagz{ tagz__(m, *a, &b) }
        
          when :processing_instruction
            m = $1
            tagz{ tagz_?(m, *a) }

          when :close_tag
            m = $1
            tagz{ __tagz(m, *a, &b) }

          when :element
            Tagz.element.new(*a, &b)

          when :puts
            tagz do
              tagz.push("\n")
              unless a.empty?
                tagz.push(a.join)
                tagz.push("\n")
              end
            end
        end
      end
  end


# supporting code
#
  module Tagz
  # singleton_class access for ad-hoc method adding from inside namespace
  #
    def Tagz.singleton_class(&block)
      @singleton_class ||= (
        class << Tagz
          self
        end
      )
      block ? @singleton_class.module_eval(&block) : @singleton_class
    end

  # hide away our own shit to minimize namespace pollution
  #
    class << Tagz
      module Namespace
        namespace = self

        Tagz.singleton_class{
          define_method(:namespace){ |*args|
            if args.empty?
              namespace
            else
              namespace.const_get(args.first.to_sym)
            end
          }
        }

        Tagz.singleton_class{
          define_method(:process_attributes){ |options, &block|
            attributes = ''
            unless options.empty?
              booleans = []
              options.each do |key, value|
                case key.to_s
                when /#{Tagz.namespace(:Boolean)}/
                  value = value.to_s =~ %r/\Atrue\Z/imox ? nil : "\"#{ key.to_s.downcase.strip }\""
                  booleans.push([key, value].compact)
                  next
                else
                  block.call(key, value) if block
                end

                key = Tagz.escape_key(key)
                value = Tagz.escape_value(value)

                if value =~ %r/"/
                  raise ArgumentError, value if value =~ %r/'/
                  value = "'#{ value }'"
                else
                  raise ArgumentError, value if value =~ %r/"/
                  value = "\"#{ value }\""
                end

                attributes << ' ' << [key, value].join('=')
              end
              booleans.each do |kv|
                attributes << ' ' << kv.compact.join('=')
              end
            end
            attributes
          }
        }

        Boolean = %r[
          \A checked  \Z |
          \A selected \Z |
          \A disabled \Z |
          \A readonly \Z |
          \A autofocus \Z |
          \A multiple \Z |
          \A ismap    \Z |
          \A defer    \Z |
          \A declare  \Z |
          \A noresize \Z |
          \A nowrap   \Z |
          \A noshade  \Z |
          \A compact  \Z 
        ]iomx

        class HTMLSafe < ::String
          def html_safe
            self
          end

          def html_safe?
            true
          end

          def to_s
            self
          end
        end

        class Document < HTMLSafe
          def Document.for(other)
            Document === other ? other : Document.new(other.to_s)
          end

          def element
            Tagz.element.new(*a, &b)
          end
          alias_method 'e', 'element'

          alias_method 'write', 'concat'
          alias_method 'push', 'concat'

          def << obj
            if obj.respond_to?(:html_safe?) and obj.html_safe?
              super obj.to_s
            else
              super Tagz.escape_content(obj)
            end

            self
          end

          def concat(obj)
            self << obj
          end

          def escape(string)
            Tagz.escape(string)
          end
          alias_method 'h', 'escape'

          def puts(string)
            write "#{ string }\n"
          end

          def raw(string)
            push Document.for(string)
          end

          def document
            self
          end
          alias_method 'doc', 'document'

          def + other
            self.dup << other
          end

          def to_s
            self
          end

          def to_str
            self
          end

          #-- new XML support

          attr_reader :prefix

          def to_xml(encoding = 'utf-8')
            # need to make sure all the namespaces are defined
            fix_root_ns
            "<?xml version=\"1.0\" encoding=\"#{encoding}\" ?>" << to_s
          end

          def register_namespace(prefix, nsuri)
            @nsm.register_namespace(prefix, nsuri)
          end

          def register_default_namespace(nsuri)
            @nsm.register_default_namespace(nsuri)
          end

          def using_namespace(nsuri = nil, defined = false)
            if nsuri
              unless @prefix = @nsm.get_prefix(nsuri)
                @prefix = @nsm.autoregister_namespace(nsuri)
#                STDOUT.puts "AUTOREGISTER: #{@prefix}:#{nsuri}"
              end
              @nsdef[@prefix] = defined
            end
            @nslist << @prefix
          end

          def reset_namespace(prefix = nil, uri = nil)
            if prefix && uri
              @nsm.clear
              prefix = (prefix == "" || prefix.nil? ? :default : prefix)
              @nsm.register_namespace(prefix, uri)
              @nsdef[prefix] = false unless @nsdef.has_key? prefix
            else
              @nslist.pop
              prefix = @nslist[-1]
            end
            @prefix = prefix
          end

          def node(name)
            @prefix && @prefix != :default ? "#{prefix}:#{name}" : name
          end

          def namespace_attrs
            @nsm.namespace_list.each_with_object({}) do |(k, v), h|
              h.merge(nsattr(k, v))
            end
          end

          def has_prefix?
            !@prefix.nil?
          end

          def get_prefix(uri)
            @nsm.get_prefix(uri)
          end

          def depth
            @nslist.size
          end

          def fix_root_ns
            i = index(/(?<!\?)>/)
            attrs = ""
            @nsdef.each do |k,v|
              unless v
                ns = nsattr(k, @nsm.get_uri(k)).flatten
                attrs << " #{ns[0]}=\"#{ns[1]}\""
              end
            end
            insert(i, attrs)
          end

          def nsattr(prefix, uri)
            h = {}
            @nsdef[prefix] = true
            if :default == prefix
              h[:xmlns] = uri
            else
              h["xmlns:#{prefix}"] = uri
            end
            h
          end

          def initialize(*a)
            super(*a)
            @nsm = XMLNamespaceManager.new
            @prefix = nil
            @nslist = []
            @nsdef = {}
            @pending_ns = false
          end
        end
        Tagz.singleton_class{ define_method(:document){ Tagz.namespace(:Document) } }

        class Element < ::String
          def Element.attributes(options)
            unless options.empty?
              ' ' << 
                options.map do |key, value|
                  key = Tagz.escape_key(key)
                  value = Tagz.escape_value(value)
                  if value =~ %r/"/
                    raise ArgumentError, value if value =~ %r/'/
                    value = "'#{ value }'"
                  else
                    raise ArgumentError, value if value =~ %r/"/
                    value = "\"#{ value }\""
                  end
                  [key, value].join('=')
                end.join(' ')
            else
              ''
            end
          end

          attr 'name'

          def initialize(name, *argv, &block)
            options = {}
            content = []

            argv.each do |arg|
              case arg
                when Hash
                  options.update arg
                else
                  content.push arg
              end
            end

            content.push block.call if block
            content.compact!

            @name = name.to_s

            if content.empty?
              replace "<#{ @name }#{ Element.attributes options }>"
            else
              replace "<#{ @name }#{ Element.attributes options }>#{ content.join }</#{ name }>"
            end
          end
        end
        Tagz.singleton_class{ define_method(:element){ Tagz.namespace(:Element) } }
        
        class XMLNamespaceManager
          def initialize
            @nsxuri = {}
            @nsxpfx = {}
          end

          def set_default_namespace(nsuri)
            register_namespace(:default, nsuri)
          end

          def register_namespace(prefix, uri)
            prefix, uri = param_fix(prefix, uri)
            if (p = get_prefix(uri)) && prefix != p
              raise ArgumentError.new("namespace URI '#{uri}' already registered with prefix '#{p}'")
            end
            if (u = get_uri(prefix)) && uri != u
              raise ArgumentError.new("prefix '#{prefix}' already registered with URI '#{u}'")
            end

            @nsxuri[uri] = prefix
            @nsxpfx[prefix] = uri
            self
          end

          def unregister_namespace(prefix, uri)
            prefix, uri = param_fix(prefix, uri)
            if (u = get_uri(prefix)) \
                && (p = get_prefix(uri)) \
                && prefix == p \
                && uri == u
              @nsxuri.delete(uri)
              @nsxpfx.delete(prefix)
            else
              raise ArgumentError.new("prefix '#{prefix}' not registered for URI '#{uri}'")
            end
            self
          end

          def autoregister_namespace(uri)
            uri = uri.to_s

            if p = get_prefix(uri)
              raise ArgumentError.new("namespace URI '#{uri}' already registered with prefix '#{p}'")
            end

            prefix = generate_prefix
            register_namespace(prefix, uri)
            prefix
          end

          def get_prefix(nsuri)
            @nsxuri[nsuri.to_s]
          end

          def get_uri(prefix)
            @nsxpfx[prefix.to_s]
          end

          def clear
            @nsxuri.clear
            @nsxpfx.clear
          end

          def namespace_list
            @nsxpfx.clone
          end

        private
          def param_fix(prefix, uri)
            prefix = prefix.to_s unless prefix == :default
            [ prefix, uri = uri.to_s ]
          end
          
          def generate_prefix
            ('a'..'z').each do |l|
              ('0'..'9').each do |d|
                p = l + d
                return p unless @nsxpfx.has_key? p
              end
            end
          end
        end

        NoEscapeContentProc = lambda{|*contents| contents.join}
        Tagz.singleton_class{ define_method(:no_escape_content_proc){ Tagz.namespace(:NoEscapeContentProc) } }
        EscapeContentProc = lambda{|*contents| Tagz.escapeHTML(contents.join)}
        Tagz.singleton_class{ define_method(:escape_content_proc){ Tagz.namespace(:EscapeContentProc) } }

        NoEscapeKeyProc = lambda{|*values| values.join}
        Tagz.singleton_class{ define_method(:no_escape_key_proc){ Tagz.namespace(:NoEscapeKeyProc) } }
        EscapeKeyProc = lambda{|*values| Tagz.escapeAttribute(values).sub(/\Adata_/imox, 'data-') }
        Tagz.singleton_class{ define_method(:escape_key_proc){ Tagz.namespace(:EscapeKeyProc) } }

        NoEscapeValueProc = lambda{|*values| values.join}
        Tagz.singleton_class{ define_method(:no_escape_value_proc){ Tagz.namespace(:NoEscapeValueProc) } }
        EscapeValueProc = lambda{|*values| Tagz.escapeAttribute(values)}
        Tagz.singleton_class{ define_method(:escape_value_proc){ Tagz.namespace(:EscapeValueProc) } }

        module Globally; include Tagz; end
        Tagz.singleton_class{ define_method(:globally){ Tagz.namespace(:Globally) } }

        module Privately; include Tagz; end
        Tagz.singleton_class{ define_method(:privately){ Tagz.namespace(:Privately) } }
      end
    end

  # escape utils
  #
    def Tagz.escape_html_map
      @escape_html_map ||= { '&' => '&amp;',  '>' => '&gt;',   '<' => '&lt;', '"' => '&quot;', "'" => '&#39;' }
    end

    def Tagz.escape_html_once_regexp
      @escape_html_once_regexp ||= /["><']|&(?!([a-zA-Z]+|(#\d+));)/
    end

    def Tagz.escape_html(s)
      s = s.to_s

      if Tagz.html_safe?(s)
        s
      else
        Tagz.html_safe(s.gsub(/[&"'><]/, Tagz.escape_html_map))
      end
    end

    def Tagz.escape_html_once(s)
      result = s.to_s.gsub(Tagz.html_escape_once_regexp){|_| Tagz.escape_html_map[_]}

      Tagz.html_safe?(s) ? Tagz.html_safe(result) : result
    end

    def Tagz.escapeHTML(*strings)
      Tagz.escape_html(strings.join)
    end

    def Tagz.escape(*strings)
      Tagz.escape_html(strings.join)
    end

    def Tagz.escapeAttribute(*strings)
      Tagz.escape_html(strings.join)
    end

  # raw utils
  #
    def Tagz.html_safe(*args, &block)
      html_safe = namespace(:HTMLSafe)

      if args.empty? and block.nil?
        return html_safe
      end

      first = args.first

      case
        when first.is_a?(html_safe)
          return first

        when args.size == 1
          string = first
          html_safe.new(string)

        else
          string = [args, (block ? block.call : nil)].flatten.compact.join(' ')
          html_safe.new(string)
      end
    end

    def Tagz.html_safe?(string)
      string.html_safe? rescue false
    end

    def Tagz.raw(*args, &block)
      Tagz.html_safe(*args, &block)
    end

    def Tagz.h(string)
      Tagz.escape_html(string)
    end

  # generate code for escape configuration
  #
    %w( key value content ).each do |type|

      module_eval <<-__, __FILE__, __LINE__
        def Tagz.escape_#{ type }!(*args, &block)
          previous = @escape_#{ type } if defined?(@escape_#{ type })
          unless args.empty?
            value = args.shift
            value = Tagz.escape_#{ type }_proc if value==true
            value = Tagz.no_escape_#{ type }_proc if(value==false or value==nil)
            @escape_#{ type } = value.to_proc
            if block
              begin
                return block.call()
              ensure
                @escape_#{ type } = previous
              end
            else
              return previous
            end
          end
          @escape_#{ type }
        end

        def Tagz.escape_#{ type }s!(*args, &block)
          Tagz.escape_#{ type }!(*args, &block)
        end

        def Tagz.escape_#{ type }(value)
          @escape_#{ type }.call(value.to_s)
        end
      __

    end

  # configure tagz escaping
  #
    def Tagz.escape!(options = {})
      options = {:keys => options, :values => options, :content => options} unless options.is_a?(Hash)

      escape_keys = options[:keys]||options['keys']||options[:key]||options['key']
      escape_values = options[:values]||options['values']||options[:value]||options['value']
      escape_contents = options[:contents]||options['contents']||options[:content]||options['content']

      Tagz.escape_keys!(!!escape_keys)
      Tagz.escape_values!(!!escape_values)
      Tagz.escape_contents!(!!escape_contents)
    end
    def Tagz.i_know_what_the_hell_i_am_doing!
      escape!(false)
    end
    def Tagz.i_do_not_know_what_the_hell_i_am_doing!
      escape!(true)
    end
    def Tagz.xml_mode!
      Tagz.escape!(
        :keys => true,
        :values => true,
        :contents => true
      )
    end
    def Tagz.html_mode!
      Tagz.escape!(
        :keys => true,
        :values => false,
        :content => false
      )
    end

  # allow access to instance methods via module handle
  #
    %w( tagz tagz__ __tagz method_missing ).each{|m| module_function(m)}
  end

  def Tagz(*argv, &block)
    (argv.empty? and block.nil?) ? ::Tagz : Tagz.tagz(*argv, &block)
  end

  def Tagz_(*argv, &block)
    (argv.empty? and block.nil?) ? ::Tagz : Tagz.tagz(*argv, &block)
  end

  Tagz.escape!(true)
end
