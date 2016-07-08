require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am_manager'
require 'uuid'

module OMF::SFA::AM::Rest

  # Handles an individual resource
  #
  class ResourceHandler < RestHandler

    # Return the handler responsible for requests to +path+.
    # The default is 'self', but override if someone else
    # should take care of it
    #
    def find_handler(path, opts)
      #opts[:account] = @am_manager.get_default_account
      opts[:resource_uri] = path.join('/')
      if path.size == 0 || path.size == 1
        debug "find_handler: path: '#{path}' opts: '#{opts.inspect}'"
        return self
      elsif path.size == 3 #/resources/type1/UUID/type2
        opts[:source_resource_uri] = path[0]
        opts[:source_resource_uuid] = path[1]
        opts[:target_resource_uri] = path[2]
        raise OMF::SFA::AM::Rest::BadRequestException.new "'#{opts[:source_resource_uuid]}' is not a valid UUID." unless UUID.validate(opts[:source_resource_uuid])
        require 'omf-sfa/am/am-rest/resource_association_handler'
        return OMF::SFA::AM::Rest::ResourceAssociationHandler.new(@am_manager, opts)
      else
        raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
      end
    end

    # List a resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the requested resource.
    def on_get(resource_uri, opts)
      debug "on_get: #{resource_uri}"
      authenticator = opts[:req].session[:authorizer]
      unless resource_uri.empty?
        resource_type, resource_params = parse_uri(resource_uri, opts)
        if resource_uri == 'leases'
          status_types = ["pending", "accepted", "active"] # default value
          status_types = resource_params[:status].split(',') unless resource_params[:status].nil?

          acc_desc = {}
          acc_desc[:urn] = resource_params.delete(:account_urn) if resource_params[:account_urn]
          acc_desc[:uuid] = resource_params.delete(:account_uuid) if resource_params[:account_uuid]
          account = @am_manager.find_account(acc_desc, authenticator) unless acc_desc.empty?
          
          resource =  @am_manager.find_all_leases(account, status_types, authenticator)
          return show_resource(resource, opts)
        end
        descr = {}
        descr.merge!(resource_params) unless resource_params.empty?
        opts[:path] = opts[:req].path.split('/')[0 .. -2].join('/')
        descr[:account_id] = @am_manager.get_scheduler.get_nil_account.id if eval("OMF::SFA::Model::#{resource_type}").can_be_managed?
        if descr[:name].nil? && descr[:uuid].nil?
          resource =  @am_manager.find_all_resources(descr, resource_type, authenticator)
        else
          resource = @am_manager.find_resource(descr, resource_type, authenticator)
        end
        return show_resource(resource, opts)
      else
        debug "list all resources."
        resource = @am_manager.find_all_resources_for_account(opts[:account], authenticator)
      end
      raise UnknownResourceException, "No resources matching the request." if resource.empty?
      show_resource(resource, opts)
    end

    # Update an existing resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the updated resource.
    def on_put(resource_uri, opts)
      debug "on_put: #{resource_uri}"
      resource = update_resource(resource_uri, true, opts)
      show_resource(resource, opts)
    end

    # Create a new resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_post(resource_uri, opts)
      debug "on_post: #{resource_uri}"
      resource = update_resource(resource_uri, false, opts)
      show_resource(resource, opts)
    end

    # Deletes an existing resource
    # 
    # @param [String] request URI
    # @param [Hash] options of the request
    # @return [String] Description of the created resource.
    def on_delete(resource_uri, opts)
      debug "on_delete: #{resource_uri}"
      delete_resource(resource_uri, opts)
      show_resource(nil, opts)
    end


    # Update resource(s) referred to by +resource_uri+. If +clean_state+ is
    # true, reset any other state to it's default.
    #
    def update_resource(resource_uri, clean_state, opts)
      body, format = parse_body(opts)
      resource_type, resource_params = parse_uri(resource_uri, opts)
      authenticator = opts[:req].session[:authorizer]
      case format
      # when :empty
        # # do nothing
      when :xml
        resource = @am_manager.update_resources_from_xml(body.root, clean_state, opts)
      when :json
        if clean_state
          resource = update_a_resource(body, resource_type, authenticator)
        else
          resource = create_new_resource(body, resource_type, authenticator)
        end
      else
        raise UnsupportedBodyFormatException.new(format)
      end
      resource
    end


    # This methods deletes components, or more broadly defined, removes them
    # from a slice.
    #
    # Currently, we simply transfer components to the +default_sliver+
    #
    def delete_resource(resource_uri, opts)
      body, format = parse_body(opts)
      resource_type, resource_params = parse_uri(resource_uri, opts)
      authenticator = opts[:req].session[:authorizer]
      release_resource(body, resource_type, authenticator)
    end

    # Update the state of +component+ according to inforamtion
    # in the http +req+.
    #
    #
    def update_component_xml(component, modifier_el, opts)
    end

    # Return the state of +component+
    #
    # +component+ - Component to display information about. !!! Can be nil - show only envelope
    #
    def show_resource(resource, opts)
      unless about = opts[:req].path
        throw "Missing 'path' declaration in request"
      end
      path = opts[:path] || about

      case opts[:format]
      when 'xml'
        show_resources_xml(resource, path, opts)
      else
        show_resources_json(resource, path, opts)
      end
    end

    def show_resources_xml(resource, path, opts)
      #debug "show_resources_xml: #{resource}"
      opts[:href_prefix] = path
      announcement = OMF::SFA::Model::OComponent.sfa_advertisement_xml(resource, opts)
      ['text/xml', announcement.to_xml]
    end

    def show_resources_json(resources, path, opts)
      res = resources ? resource_to_json(resources, path, opts) : {response: "OK"}
      res[:about] = opts[:req].path

      ['application/json', JSON.pretty_generate({:resource_response => res}, :for_rest => true)]
    end

    def resource_to_json(resource, path, opts, already_described = {})
      debug "resource_to_json: resource: #{resource.inspect}, path: #{path}"
      if resource.kind_of? Enumerable
        res = []
        resource.each do |r|
          p = path
          res << resource_to_json(r, p, opts, already_described)[:resource]
        end
        res = {:resources => res}
      else
        #prefix = path.split('/')[0 .. -2].join('/') # + '/'
        prefix = path
        if resource.respond_to? :to_sfa_hashXXX
          debug "TO_SFA_HASH: #{resource}"
          res = {:resource => resource.to_sfa_hash(already_described, :href_prefix => prefix)}
        else
          rh = resource.to_hash

          # unless (account = resource.account) == @am_manager.get_default_account()
            # rh[:account] = {:uuid => account.uuid.to_s, :name => account.name}
          # end
          res = {:resource => rh}
        end
      end
      res
    end

    protected

    def parse_uri(resource_uri, opts)
      params = opts[:req].params.symbolize_keys!
      params.delete("account")

      return ['mapper', params] if opts[:req].env["REQUEST_PATH"] == '/mapper'

      case resource_uri
      when "cmc"
        type = "ChasisManagerCard"
      when "wimax"
        type = "WimaxBaseStation"
      when "lte"
        type = "ENodeB"
      when "openflow"
        type = "OpenflowSwitch"
      else
        type = resource_uri.singularize.camelize
        begin
          eval("OMF::SFA::Model::#{type}").class
        rescue NameError => ex
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource type '#{resource_uri}'."
        end
      end
      [type, params]
    end

    # Create a new resource
    #
    # @param [Hash] Describing properties of the requested resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [OResource] The resource created
    # @raise [UnknownResourceException] if no resource can be created
    #
    def create_new_resource(resource_descr, type_to_create, authorizer)
      debug "create_new_resource: resource_descr: #{resource_descr}, type_to_create: #{type_to_create}"
      authorizer.can_create_resource?(resource_descr, type_to_create)

      if type_to_create == "Lease" #Lease is a unigue case, needs special treatment
        raise OMF::SFA::AM::Rest::BadRequestException.new "Attribute account is mandatory." if resource_descr[:account].nil? && resource_descr[:account_attributes].nil?
        raise OMF::SFA::AM::Rest::BadRequestException.new "Attribute components is mandatory." if (resource_descr[:components].nil? || resource_descr[:components].empty?) && (resource_descr[:components_attributes].nil? || resource_descr[:components_attributes].empty?)
        raise OMF::SFA::AM::Rest::BadRequestException.new "Attributes valid_from and valid_until are mandatory." if resource_descr[:valid_from].nil? || resource_descr[:valid_until].nil?

        res_descr = {}
        res_descr[:name] = resource_descr[:name]
        res_descr[:valid_from] = resource_descr[:valid_from]
        res_descr[:valid_until] = resource_descr[:valid_until]
        ac_desc = resource_descr[:account] || resource_descr[:account_attributes]
        ac = OMF::SFA::Model::Account.first(ac_desc)
        raise OMF::SFA::AM::Rest::UnknownResourceException.new "Account with description '#{ac_desc}' does not exist." if ac.nil? 
        raise OMF::SFA::AM::Rest::NotAuthorizedException.new "Account with description '#{ac_desc}' is closed." unless ac.active?
        res_descr[:account_id] = ac.id
        lease = @am_manager.find_or_create_lease(res_descr, authorizer)

        comps = resource_descr[:components] || resource_descr[:components_attributes]
        nil_account_id = @am_manager._get_nil_account.id
        components = []
        comps.each do |c|
          desc = {}
          desc[:account_id] = nil_account_id
          desc[:uuid] = c[:uuid] unless c[:uuid].nil?
          desc[:name] = c[:name] unless c[:name].nil?
          if k = OMF::SFA::Model::Resource.first(desc)
            components << k
          end
        end 

        scheduler = @am_manager.get_scheduler
        comps = []
        components.each do |comp|
          comps << c = scheduler.create_child_resource({uuid: comp.uuid, account_id: ac.id}, comp[:type].to_s.split('::').last)
          unless scheduler.lease_component(lease, c)
            scheduler.delete_lease(lease)
            @am_manager.release_resources(comps, authorizer)
            raise NotAuthorizedException.new "Reservation for the resource '#{c.name}' failed. The resource is either unavailable or a policy quota has been exceeded."
          end
        end
        resource = lease
      else
        if resource_descr.kind_of? Array
          descr = []
          resource_descr.each do |res|
            res_descr = {}
            res_descr.merge!({uuid: res[:uuid]}) if res.has_key?(:uuid)
            res_descr.merge!({name: res[:name]}) if res.has_key?(:name)
            descr << res_descr unless eval("OMF::SFA::Model::#{type_to_create}").first(res_descr)
          end
          raise OMF::SFA::AM::Rest::BadRequestException.new "No resources described in description #{resource_descr} is valid. Maybe all the resources alreadt=y exist." if descr.empty?
        elsif resource_descr.kind_of? Hash
          descr = {}
          descr.merge!({uuid: resource_descr[:uuid]}) if resource_descr.has_key?(:uuid)
          descr.merge!({name: resource_descr[:name]}) if resource_descr.has_key?(:name)
        
          if descr.empty?
            raise OMF::SFA::AM::Rest::BadRequestException.new "Resource description is '#{resource_descr}'."
          else
            raise OMF::SFA::AM::Rest::BadRequestException.new "Resource with descr '#{descr} already exists'." if eval("OMF::SFA::Model::#{type_to_create}").first(descr)
          end
        end

        if resource_descr.kind_of? Array
          resource = []
          resource_descr.each do |res_desc|
            resource << eval("OMF::SFA::Model::#{type_to_create}").create(res_desc)
            @am_manager.manage_resource(resource.last) if resource.last.account.nil?
            if type_to_create == 'Account'
              @am_manager.liaison.create_account(resource.last)
            end
          end
        elsif resource_descr.kind_of? Hash
          resource = eval("OMF::SFA::Model::#{type_to_create}").create(resource_descr)
          @am_manager.manage_resource(resource) if resource.class.can_be_managed?
          if type_to_create == 'Account'
            @am_manager.liaison.create_account(resource)
          end
        end
      end
      resource
    end

    # Update a resource
    #
    # @param [Hash] Describing properties of the requested resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [OResource] The resource created
    # @raise [UnknownResourceException] if no resource can be created
    #
    def update_a_resource(resource_descr, type_to_create, authorizer)
      descr = {}
      descr.merge!({uuid: resource_descr[:uuid]}) if resource_descr.has_key?(:uuid)
      descr.merge!({name: resource_descr[:name]}) if descr[:uuid].nil? && resource_descr.has_key?(:name)
      unless descr.empty?
        if resource = eval("OMF::SFA::Model::#{type_to_create}").first(descr)
          authorizer.can_modify_resource?(resource, type_to_create)
          resource.update(resource_descr)
          @am_manager.get_scheduler.update_lease_events_on_event_scheduler(resource) if type_to_create == 'Lease'
          # @am_manager.manage_resource(resource)
        else
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource with descr'#{resource_descr}'."
        end
      end
      resource
    end

    # Release a resource
    #
    # @param [Hash] Describing properties of the requested resource
    # @param [String] Type to create
    # @param [Authorizer] Defines context for authorization decisions
    # @return [OResource] The resource created
    # @raise [UnknownResourceException] if no resource can be created
    #
    def release_resource(resource_descr, type_to_release, authorizer)
      if type_to_release == "Lease" #Lease is a unigue case, needs special treatment
        if resource = OMF::SFA::Model::Lease.first(resource_descr)
          @am_manager.release_lease(resource, authorizer)
        else
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown Lease with descr'#{resource_descr}'."
        end
      else
        authorizer.can_release_resource?(resource_descr)
        if resource = eval("OMF::SFA::Model::#{type_to_release}").first(resource_descr)
          if type_to_release == 'Account'
            @am_manager.liaison.close_account(resource)
          end
          resource.destroy
        else
          raise OMF::SFA::AM::Rest::UnknownResourceException.new "Unknown resource with descr'#{resource_descr}'."
        end
      end
      resource
    end

    # Before create a new resource, parse the resource description and alternate existing resources.
    #
    # @param [Hash] Resource Description
    # @return [Hash] New Resource Description
    # @raise [UnknownResourceException] if no resource can be created
    #
    def parse_resource_description(resource_descr, type_to_create)
      resource_descr.each do |key, value|
        debug "checking prop: '#{key}': '#{value}': '#{type_to_create}'"
        if value.kind_of? Array
          value.each_with_index do |v, i|
            if v.kind_of? Hash
              # debug "Array: #{v.inspect}"
              begin
                k = eval("OMF::SFA::Model::#{key.to_s.singularize.capitalize}").first(v)
                raise NameError if k.nil?
                resource_descr[key][i] = k
              rescue NameError => nex
                model = eval("OMF::SFA::Model::#{type_to_create}.get_oprops[key][:__type__]")
                resource_descr[key][i] = (k = eval("OMF::SFA::Model::#{model}").first(v)) ? k : v
              end
            end
          end
        elsif value.kind_of? Hash
          debug "Hash: #{key.inspect}: #{value.inspect}"
          begin
            k = eval("OMF::SFA::Model::#{key.to_s.singularize.capitalize}").first(value)
            raise NameError if k.nil?
            resource_descr[key] = k
          rescue NameError => nex
            model = eval("OMF::SFA::Model::#{type_to_create}.get_oprops[key][:__type__]")
            resource_descr[key] = (k = eval("OMF::SFA::Model::#{model}").first(value)) ? k : value
          end
        end
      end
      resource_descr
    end
  end # ResourceHandler
end # module
