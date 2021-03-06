

require 'nokogiri'

# require 'omf-sfa/resource/sliver'
# require 'omf-sfa/resource/node'
# require 'omf-sfa/resource/link'
# require 'omf-sfa/resource/interface'

require 'set'
require 'json'

require 'omf_common/lobject'
require 'omf-sfa/am/am_manager'


module OMF::SFA::AM::Rest

  class RackException < Exception
    attr_reader :reply

    def initialize(err_code, reason)
      super reason
      body = {:exception => {
        :code => err_code,
        :reason => reason
      }}
      @reply = [err_code, { 'Content-Type' => 'text/json', 'Access-Control-Allow-Origin' => '*' , 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS' }, JSON.pretty_generate(body) + "\n"]
    end

  end

  class BadRequestException < RackException
    def initialize(reason)
      super 400, reason
    end
  end

  class EmptyBodyException < RackException
    def initialize()
      super 400, "Message body is empty"
    end
  end

  class UnsupportedBodyFormatException < RackException
    def initialize(format = 'unknown')
      super 400, "Message body format '#{format}' is unsupported"
    end
  end


  class NotAuthorizedException < RackException
    def initialize(reason)
      super 401, reason
    end
  end

  class IllegalMethodException < RackException
    def initialize(reason)
      super 403, reason
    end
  end

  class UnsupportedMethodException < RackException
    def initialize()
      super 403, "Unsupported Method"
    end
  end

  class UnknownResourceException < RackException
    def initialize(reason)
      super 404, reason
    end
  end

  class MissingResourceException < RackException
    def initialize(reason)
      super 404, reason
    end
  end

  class RestHandler < OMF::Common::LObject

    def initialize(am_manager, opts = {})
      #debug "INIT>>> #{am_manager}::#{self}"
      @am_manager = am_manager
      @opts = opts
      @return_struct = { # hash
                         :code => {
                             :geni_code => ""
                         },
                         :value => '',
                         :output => ''
      }
    end

    def call(env)
      debug "call"
      begin
        req = ::Rack::Request.new(env)
        if req.request_method == 'OPTIONS'
          return [200 ,{
            'Access-Control-Allow-Origin' => '*' ,
            'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers' => 'origin, x-csrftoken, content-type, accept'
          }, ""]
        end
        content_type, body = dispatch(req)
        return [200 ,{ 'Content-Type' => content_type, 'Access-Control-Allow-Origin' => '*' , 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS' }, body]
      rescue RackException => rex
        debug rex.to_s
        # debug rex.backtrace.join("\n")
        return rex.reply
      rescue OMF::SFA::AM::InsufficientPrivilegesException => iex
        debug iex.to_s
        # debug iex.backtrace.join("\n")
        return RackException.new(401, iex.to_s).reply
      rescue OMF::SFA::AM::AMManagerException => mex
        debug mex.to_s
        # debug mex.backtrace.join("\n")
        return RackException.new(400, mex.to_s).reply
      rescue ArgumentError => aex
        debug aex.to_s
        # debug aex.backtrace.join("\n")
        return RackException.new(400, aex.to_s).reply
      rescue Exception => ex
        body = {
          :error => {
            :reason => ex.to_s,
            :bt => ex.backtrace #.select {|l| !l.start_with?('/') }
          }
        }
        warn "ERROR: #{ex}"
        debug ex.backtrace.join("\n")
        # root = _create_response('error', req = nil)
        # doc = root.document
        # reason = root.add_child(Nokogiri::XML::Element.new('reason', doc))
        # reason.content = ex.to_s
        # reason = root.add_child(Nokogiri::XML::Element.new('bt', doc))
        # reason.content = ex.backtrace.join("\n\t")
        return [500, { "Content-Type" => 'application/json', 'Access-Control-Allow-Origin' => '*', 'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS' }, JSON.pretty_generate(body) + "\n"]
      end
    end

    def on_get(resource_uri, opts)
      debug 'get: resource_uri: "', resource_uri, '"'
      if resource_uri
        resource = opts[:resource]
        show_resource_status(resource, opts)
      else
        show_resource_list(opts)
      end
    end

    def on_post(resource_uri, opts)
      #debug 'POST: resource_uri "', resource_uri, '" - ', opts.inspect
      description, format = parse_body(opts, [:json, :form])
      debug 'POST(', resource_uri, '): body(', format, '): "', description, '"'

      if resource = opts[:resource]
        debug 'POST: Modify ', resource
        modify_resource(resource, description, opts)
      else
        debug 'POST: Create? ', description.class
        if description.is_a? Array
          resources = description.map do |d|
            create_resource(d, opts)
          end
          return show_resources(resources, nil, opts)
        else
          debug 'POST: Create ', resource_uri
          if resource_uri
            if UUID.validate(resource_uri)
              description[:uuid] = resource_uri
            else
              description[:name] = resource_uri
            end
          end
          resource = create_resource(description, opts, resource_uri)
        end
      end

      if resource
        show_resource_status(resource, opts)
      elsif context = opts[:context]
        show_resource_status(context, opts)
      else
        raise "Report me. Should never get here"
      end
    end

    def on_delete(resource_uri, opts)
      if resource = opts[:resource]
        if (context = opts[:context])
          remove_resource_from_context(resource, context)
          res = show_resource_status(resource, opts)
        else
          debug "Delete resource #{resource}"
          res = show_deleted_resource(resource.uuid)
          resource.destroy
        end
      else
        # Delete ALL resources of this type
        raise OMF::SFA::AM::Rest::BadRequestException.new "I'm sorry, Dave. I'm afraid I can't do that."
      end
      resource.reload
      return res
    end


    def find_handler(path, opts)
      debug "rest handler"
      debug "find_handler: path; '#{path}' opts: #{opts}"
      resource_id = opts[:resource_uri] = path.shift
      opts[:resource] = nil
      if resource_id
        resource = opts[:resource] = find_resource(resource_id)
      end
      return self if path.empty? # auto sumvainei stin apli periptwsi

      raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource '#{resource_id}'." unless resource
      opts[:context] = resource
      comp = path.shift
      if (handler = @coll_handlers[comp.to_sym])
        opts[:resource_uri] = path.join('/')
        if handler.is_a? Proc
          return handler.call(path, opts)
        end
        return handler.find_handler(path, opts)
      end
      raise UnknownResourceException.new "Unknown sub collection '#{comp}' for '#{resource_id}:#{resource.class}'."
    end



    protected
    

    def modify_resource(resource, description, opts)
      if description[:uuid]
        raise "Can't change uuid" unless  description[:uuid] == resource.uuid.to_s
      end
      description.delete(:href)
      resource.update(description) ? resource : nil
      #raise UnsupportedMethodException.new
    end


    def create_resource(description, opts, resource_uri = nil)
      debug "Create: #{description.class}--#{description}"

      if resource_uri
        if UUID.validate(resource_uri)
          description[:uuid] = resource_uri
        else
          description[:name] = resource_uri
        end
      end

      # Let's find if the resource already exists. If yes, just modify it
      if uuid = description[:uuid]
        debug 'Trying to find resource ', uuid, "'"
        resource = @resource_class.first(uuid: uuid)
      end
      if resource
        modify_resource(resource, description, opts)
      else
        resource = @resource_class.create(description)
        debug "Created: #{resource}"
      end
      if (context = opts[:context])
        add_resource_to_context(resource, context)
      end
      return resource
    end

    def add_resource_to_context(user, context)
      raise UnsupportedMethodException.new
    end

    def remove_resource_from_context(user, context)
      raise UnsupportedMethodException.new
    end


    # Extract information from the request object and
    # store them in +opts+.
    #
    # Extract information from the request object and
    # store them in +opts+.
    #
    def populate_opts(req, opts)
      path = req.path_info.split('/').select { |p| !p.empty? }
      opts[:req] = req
      if @opts[:semantic] # TODO OPTIMIZE
        opts[:format] = 'ttl'
      else
        opts[:format] = req['format'] || 'json' #json by default
      end
      debug "populate opts"
      opts[:target] = find_handler(path, opts) # gyrnatai o resource_handler
      #opts[:target].inspect
      opts
    end
    

    def parse_body(opts, allowed_formats = [:json, :xml])
      req = opts[:req]
      body = req.body #req.POST
      raise EmptyBodyException.new unless body
      if body.is_a? Hash
        raise UnsupportedBodyFormatException.new('Send body raw, not as form data')
      end
      (body = body.string) if body.is_a? StringIO # A node-set is converted to a string by returning the string-value
      if body.is_a? Tempfile
        tmp = body
        body = body.read
        tmp.rewind
      end
      debug 'PARSE_BODY(ct: ', req.content_type, '): ', body.inspect # req.content_type = application/json, body.inspect = "[ {   \"name\": \"node1\",   \"hostname\": \"node1\", ... "
      unless content_type = req.content_type
        body.strip! # Removes leading and trailing whitespace from <i>str</i>.
        if ['/', '{', '['].include?(body[0])
          content_type = 'application/json'
        else
          if body.empty?
            params = req.params.inject({}){|h,(k,v)| h[k.to_sym] = v; h}
            if allowed_formats.include?(:json)
              return [params, :json]
            elsif allowed_formats.include?(:form)
              return [params, :form]
            end
          end
          # default is XML
          content_type = 'text/xml'
        end
      end
      begin
        case content_type
        when 'application/json'
          raise UnsupportedBodyFormatException.new(:json) unless allowed_formats.include?(:json)
          jb = JSON.parse(body)   # Parse the JSON document _source_ into an array of hashes and return it
          return [_rec_sym_keys(jb), :json]
        when 'text/xml'
          xb = Nokogiri::XML(body)
          raise UnsupportedBodyFormatException.new(:xml) unless allowed_formats.include?(:xml)
          return [xb, :xml]
        when 'application/x-www-form-urlencoded'
          raise UnsupportedBodyFormatException.new(:xml) unless allowed_formats.include?(:form)
          fb = req.POST
          puts "FORM: #{fb.inspect}"
          return [fb, :form]
        end
      rescue Exception => ex
        raise BadRequestException.new "Problems parsing body (#{ex})"
      end
      raise UnsupportedBodyFormatException.new(content_type)
    end

    private
    # Don't override


    def dispatch(req)
      debug "dispatch"
      opts = {}
      populate_opts(req, opts)
      #debug "OPTS>>>> #{opts.inspect}"
      method = req.request_method # GET
      target = opts[:target] #|| self
      resource_uri = opts[:resource_uri]
      case method
      when 'GET'
        res = target.on_get(resource_uri, opts)
      when 'PUT'
        res = target.on_put(resource_uri, opts)
      when 'POST'
        res = target.on_post(resource_uri, opts)
      when 'DELETE'
        res = target.on_delete(resource_uri, opts)
      else
        raise IllegalMethodException.new method
      end
    end

    def show_resource_status(resource, opts)
      if resource
        about = opts[:req].path
        props = resource.to_hash({}, :href_use_class_prefix => true, :max_levels => 1)
        props.delete(:type)
        res = {
          #:about => about,
          :type => resource.resource_type,
        }.merge!(props)
        #res = {"#{resource.resource_type}_response" => res}
      else
        res = {:error => 'Unknown resource'}
      end

      ['application/json', JSON.pretty_generate(res)]
    end




    def find_resource(resource_uri, description = {})
      descr = description.dup
      descr.delete(:resource_uri)
      if UUID.validate(resource_uri)
        descr[:uuid] = resource_uri
      else
        descr[:name] = resource_uri
      end
      if resource_uri.start_with?('urn')
        descr[:urn] = resource_uri
      end
      #authenticator = Thread.current["authenticator"]
      debug "Finding #{@resource_class}.first(#{descr})"
      @resource_class.first(descr)
    end

    def show_resources(resources, resource_name, opts)
      res_hash = resources.map do |a|
        a.to_hash_brief(:href_use_class_prefix => true)
      end
      if resource_name
        prefix = about = opts[:req].path
        res = {
          #:about => opts[:req].path,
          resource_name => res_hash
        }
      else
        res = res_hash
      end
      ['application/json', JSON.pretty_generate(res)]
    end

    def show_deleted_resource(uuid)
      res = {
        uuid: uuid,
        deleted: true
      }
      ['application/json', JSON.pretty_generate(res)]
    end

    def show_deleted_resources(uuid_a)
      res = {
        uuids: uuid_a,
        deleted: true
      }
      ['application/json', JSON.pretty_generate(res)]
    end

    # Recursively Symbolize keys of hash
    #
    def _rec_sym_keys(array_or_hash)
      if array_or_hash.is_a? Array
        return array_or_hash.map {|e| e.is_a?(Hash) ? _rec_sym_keys(e) : e }
      end

      h = {}
      array_or_hash.each do |k, v|
        if v.is_a? Hash
          v = _rec_sym_keys(v)
        elsif v.is_a? Array
          v = v.map {|e| e.is_a?(Hash) ? _rec_sym_keys(e) : e }
        end
        h[k.to_sym] = v
      end
      h
    end


  end
end

