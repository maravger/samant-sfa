require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am-rest/resource_handler'
require 'omf-sfa/am/am_manager'
require 'uuid'

module OMF::SFA::AM::Rest
  class SamantAdminHandler < RestHandler
    @@ip_whitelist = ['127.0.0.1'].freeze

    def find_handler(path, opts)
      @return_struct = { # hash
                        :code => {
                            :geni_code => ""
                        },
                        :value => '',
                        :output => ''
      }
      debug "!!!ADMIN handler!!!"
      remote_ip = opts[:req].env["REMOTE_ADDR"]
      debug "Trying to connect from >>>>> " + remote_ip
      #debug "what contains? " + @@ip_whitelist.inspect
      #debug "contains? " + @@ip_whitelist.include?(remote_ip).to_s
      #unless @@ip_whitelist.include?(remote_ip)
      #  raise OMF::SFA::AM::Rest::BadRequestException.new "Anauthorized access!"
      #end
      RDF::Util::Logger.logger.parent.level = 'off' # Worst Bug *EVER*
      if path.map(&:downcase).include? "getinfo"
        opts[:resource_uri] = :getinfo
      elsif path.map(&:downcase).include? "create"
        opts[:resource_uri] = :create
      elsif path.map(&:downcase).include? "update"
        opts[:resource_uri] = :update
      elsif path.map(&:downcase).include? "delete"
        opts[:resource_uri] = :delete
      elsif path.map(&:downcase).include? "change_state"
        opts[:resource_uri] = :change_state
      else
        raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
      end
      return self
    end

    def on_get (method, options)
      body, format = parse_body(options)
      params = body[:options]
      authorizer = options[:req].session[:authorizer]
      resources = get_info(params)
      res = OMF::SFA::AM::Rest::ResourceHandler.omn_response_json(resources, options)
      return ['application/json', JSON.pretty_generate(res)]
    end

    def on_post (method, options)
      body, format = parse_body(options)
      res_el = body[:resources]
      authorizer = options[:req].session[:authorizer]
      resources = create_or_update(res_el, false, authorizer)
      resp = OMF::SFA::AM::Rest::ResourceHandler.omn_response_json(resources, options)
      return ['application/json', JSON.pretty_generate(resp)]
    end

    def on_put (method, options)
      body, format = parse_body(options)
      if method == :change_state
        resources = body[:resources]
        resp = change_state(resources)
        # return ['application/json', JSON.pretty_generate(resp)]
      else
        res_el = body[:resources]
        authorizer = options[:req].session[:authorizer]
        resources = create_or_update(res_el, true, authorizer)
        resp = OMF::SFA::AM::Rest::ResourceHandler.omn_response_json(resources, options)
        return ['application/json', JSON.pretty_generate(resp)]
      end
    end

    def on_delete (method, options)
      body, format = parse_body(options)
      resources = body[:resources]
      authorizer = options[:req].session[:authorizer]
      resp = delete(resources, authorizer)
      return ['application/json', JSON.pretty_generate(resp)]
    end

    # Retain info based on class/urn

    def get_info(params)
      debug 'Admin ListResources: Options: ', params.inspect
      category = params[:type]
      descr = params[:description]
      descr, find_with_array_hash = find_doctor(descr)

      if category # if applied specific resource type
        debug "descr = " + descr.inspect
        resources = @am_manager.find_all_samant_resources(category, descr)
      elsif urns = params[:urns] # if applied for certain urns
        resources = @am_manager.find_all_samant_resources(nil, descr)
        resources.delete_if {|c| !urns.include?(c.to_uri.to_s)}
      end
      resources.delete_if {|c| c.to_uri.to_s.include?"/leased"} unless resources.nil?
      unless find_with_array_hash.empty?
        resources.delete_if {|c| !find_with_array_hash.values[0].include? eval("c.#{find_with_array_hash.keys[0]}")} unless resources.nil?
      end
      resources
    end

    # Create or Update SAMANT resources. If +clean_state+ is true, resources are updated, else they are created from scratch.

    def create_or_update(res_el, clean_state, authorizer)
      sparql = SPARQL::Client.new($repository)
      debug 'Admin CreateOrUpdate: resources: ', res_el.inspect

      unless res_el.is_a?(Array)
        res_el = [res_el]
      end
      resources = []
      res_el.each do |params|
        descr = params[:resource_description]
        descr = create_doctor(descr, authorizer) # Connect the objects first
        if clean_state # update
          urn = params[:urn]
          if (urn.start_with?("uuid"))
            type = "Lease"
          else
            type = OMF::SFA::Model::GURN.parse(urn).type.camelize
          end
          res = eval("SAMANT::#{type}").for(urn)
          unless sparql.ask.whether([res.to_uri, :p, :o]).true?
            raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{res.inspect}' not found. Please create that first."
          end
          authorizer.can_modify_resource?(res, type)
          res.update_attributes(descr) # Not sure if different than ".for(urn, new_descr)" regarding an already existent urn
        else # create
          if params[:type] && (params[:type].camelize == "Uxv") && !(descr.keys.find {|k| k.to_s == "hasUxVType"})
            raise OMF::SFA::AM::Rest::BadRequestException.new "Please provide a UxV type in your description."
          end
          unless params[:name] && params[:type] && params[:authority]
            raise OMF::SFA::AM::Rest::BadRequestException.new "One of the following mandatory parameters is missing: name, type, authority."
          end
          urn = OMF::SFA::Model::GURN.create(params[:name], {:type => params[:type], :domain => params[:authority]})
          type = params[:type].camelize
          descr[:hasID] = SecureRandom.uuid # Every resource must have a uuid
          descr[:hasComponentID] = urn.to_s
          descr[:resourceId] = params[:name]
          if type.downcase == "uxv"
            descr[:hasSliceID] = "urn:publicid:IDN+omf:netmode+account+__default__" # default slice_id on creation; required on allocation
          end
          res = eval("SAMANT::#{type}").for(urn, descr) # doesn't save unless you explicitly define so
          unless sparql.ask.whether([res.to_uri, :p, :o]).false?
            raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{res.inspect}' already exists."
          end
          authorizer.can_create_resource?(res, type)
          debug "Res:" + res.inspect
          res.save!
        end
        resources << res
      end
      resources
    end

    # Delete SAMANT resources

    def delete(resources, authorizer)
      sparql = SPARQL::Client.new($repository)
      debug 'Admin Delete: resources: ', resources.inspect

      unless resources.is_a?(Array)
        resources = [resources]
      end
      resources.each do |resource|
        urn = resource[:urn]
        gurn = OMF::SFA::Model::GURN.parse(resource[:urn])
        type = gurn.type.camelize
        res = eval("SAMANT::#{type}").for(urn)
        debug "res: " + res.inspect
        unless sparql.ask.whether([res.to_uri, :p, :o]).true?
          raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{res.inspect}' not found. Please create that first."
        end
        if (res.is_a?SAMANT::Uxv)||(res.is_a?SAMANT::Interface)||(res.is_a?SAMANT::System)||(res.is_a?SAMANT::SensingDevice)
          res.hasComponentID = nil # F*ing bug
          res.save!
        end
        authorizer.can_release_resource?(res)
        res.destroy!
      end
      return {:response => "Resource(s) Successfully Deleted"}
    end

    # Connect instances before creating/updating

    def create_doctor(descr, authorizer)
      sparql = SPARQL::Client.new($repository)
      descr.each do |key, value|
        debug "key = " + key.to_s
        next if key == :hasComponentID || key == :hasSliceID # These *strings* are permitted to contain the "urn" substring
        if value.is_a?(Array)
          arr_value = value
          new_array = []
          arr_value.each do |v|
            v = create_or_update(v, false, authorizer).first.uri.to_s if v.is_a?(Hash) # create the described object
            gurn = OMF::SFA::Model::GURN.parse(v) # Assumes "v" is a urn
            unless gurn.type && gurn.name
              raise OMF::SFA::AM::Rest::UnsupportedBodyFormatException.new "Invalid URN: " + v.to_s
            end
            new_res = eval("SAMANT::#{gurn.type.camelize}").for(gurn.to_s)
            unless sparql.ask.whether([new_res.to_uri, :p, :o]).true?
              raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{new_res.inspect}' not found. Please create that first."
            end
            new_array << new_res
          end
          debug "New Array contains: " + new_array.inspect
          descr[key] = new_array
        else
          value = create_or_update(value, false, authorizer).first.uri.to_s if value.is_a?(Hash) # create the described object
          if value.include? "urn" # Object found, i.e uxv, sensor etc
            gurn = OMF::SFA::Model::GURN.parse(value)
            unless gurn.type
              raise OMF::SFA::AM::Rest::UnsupportedBodyFormatException.new "Invalid URN: " + value.to_s
            end
            descr[key] = eval("SAMANT::#{gurn.type.camelize}").for(gurn.to_s)
            unless sparql.ask.whether([descr[key].to_uri, :p, :o]).true?
              raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{descr[key].inspect}' not found. Please create that first."
            end
          elsif value.include? "http" # Instance found, i.e HealthStatus, Resource Status etc
            type = value.split("#").last
            # type = value.split("#").last.chop
            type = type.chop if type[-1,1] == "/"
            debug "Type: " + type
            # new_res = eval("SAMANT::#{type}").for("")
            new_res = eval("SAMANT::#{type.upcase}")
            unless sparql.ask.whether([new_res.to_uri, :p, :o]).true?
              raise OMF::SFA::AM::Rest::BadRequestException.new "Resource '#{new_res.inspect}' not found. Please create that first."
            end
            descr[key] = new_res
          elsif value == "nil"
            descr[key] = nil
          end
        end
      end
      debug "New Hash contains: " + descr.inspect
      descr
    end

    # Find instances

    def find_doctor(descr)
      find_with_array_hash = Hash.new
      descr.each do |key,value|
        next if key == :hasComponentID || key == :hasSliceID
        if value.is_a?(Hash)
          new_value = get_info(value).first.uri.to_s
          descr[key] = RDF::URI(new_value)
        elsif value.is_a?(Array)
          arr_value = value
          new_array = []
          arr_value.each do |v|
            if v.include? "http" or v.include? "urn"
              new_array << RDF::URI(v).to_uri
            end
          end
          find_with_array_hash[key] = new_array
          puts "Array find fix, hash contains:"
          puts find_with_array_hash.inspect
          descr.delete(key)
        elsif value.include? "http" or value.include? "urn" # Instance found, i.e HealthStatus, Resource Status etc
          descr[key] = RDF::URI(value)
        end
      end
      debug "New descr contains: " + descr.inspect
      return descr, find_with_array_hash
    end

    # Change Lease state

    def change_state(resources)
      debug "I'm in change state!"
      value = {}
      value[:geni_slivers] = []
      unless resources.is_a?(Array)
        resources = [resources]
      end
      resources.each do |resource|
        uuid = resource[:urn]
        if ["ALLOCATED", "CANCELLED"].include? resource[:state].upcase
          state = eval("SAMANT::#{resource[:state].upcase}")
        else
          @return_struct[:code][:geni_code] = 12 # Search Failed
          @return_struct[:output] = "Unkown state provided"
          @return_struct[:value] = ''
          return ['application/json', JSON.pretty_generate(@return_struct)]
        end
        l_uuid = uuid.gsub("uuid:", "")
        debug "Looking for Lease with uuid: " + l_uuid
        url = "http://147.102.22.105:8080/openrdf-sesame/repositories/samRemoteClean"
        Spira.repository = RDF::Sesame::Repository.new(url)
        lease = SAMANT::Lease.find(:all, :conditions => { :hasID => l_uuid} ).first
        if lease.nil?
          @return_struct[:code][:geni_code] = 12 # Search Failed
          @return_struct[:output] = "Lease not found!"
          @return_struct[:value] = ''
          return ['application/json', JSON.pretty_generate(@return_struct)]
        end
        if lease.hasReservationState.uri == SAMANT::CANCELLED.uri
          @return_struct[:code][:geni_code] = 12 # Search Failed
          @return_struct[:output] = "Cannot change cancelled lease!"
          @return_struct[:value] = ''
          return ['application/json', JSON.pretty_generate(@return_struct)]
        end
        lease.hasReservationState = state
        lease.save
        lease.isReservationOf.map do |resource|
          lease.hasReservationState.uri == SAMANT::ALLOCATED.uri ? resource.hasResourceStatus =
              SAMANT::BOOKED : resource.hasResourceStatus = SAMANT::RELEASED # PRESENT STATE
          resource.save
        end
        if lease.hasReservationState.uri == SAMANT::CANCELLED
          @am_manager.get_scheduler.release_samant_lease(lease)
        end
        tmp = {}
        tmp[:geni_sliver_urn]         = lease.to_uri.to_s
        tmp[:geni_expires]            = lease.expirationTime.to_s
        tmp[:geni_allocation_status]  = if lease.hasReservationState.uri == SAMANT::ALLOCATED.uri then "geni_allocated"
                                        else "geni_unallocated"
                                        end
        value[:geni_slivers] << tmp
      end
      @return_struct[:code][:geni_code] = 0
      @return_struct[:value] = value
      @return_struct[:output] = ''
      return ['application/json', JSON.pretty_generate(@return_struct)]
    end

  end
end
