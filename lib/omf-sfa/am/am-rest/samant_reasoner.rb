require 'omf-sfa/am/am-rest/rest_handler'
require 'omf-sfa/am/am-rest/resource_handler'
require 'omf-sfa/am/am_manager'
require 'uuid'
require_relative '../../omn-models/resource.rb'
require_relative '../../omn-models/populator.rb'
require 'pathname'

module OMF::SFA::AM::Rest

  class SamantReasoner < RestHandler

    def find_handler(path, opts)
      debug "!!!SAMANT reasoner!!!"
      RDF::Util::Logger.logger.parent.level = 'off' # Worst Bug *EVER*
      # debug "PATH = " + path.inspect
      # Define method called
      if path.map(&:downcase).include? "uxv-endurance"
        opts[:resource_uri] = :endurance
      elsif path.map(&:downcase).include? "uxv-distance"
        opts[:resource_uri] = :distance
      elsif path.map(&:downcase).include? "uxv"
        opts[:resource_uri] = :uxv
      else
        raise OMF::SFA::AM::Rest::BadRequestException.new "Invalid URL."
      end
      return self
    end

    # GET:
    #
    # @param method used to select which functionality is selected
    # @param [Hash] options of the request
    # @return [String] Description of the requested resource.

    def on_get (method, options)
      if method == :endurance
        endurance_distance(method.to_s, options)
      elsif method == :distance
        # distance(options)
        endurance_distance(method.to_s, options)
      elsif method == :uxv
        uxv(options)
      end
    end

    def endurance_distance(method, options)
      path = options[:req].env["REQUEST_PATH"]

      # Transform path to resources

      path_ary = Pathname(path).each_filename.to_a
      # TODO consider changing :resourceId to :hasID *generally*
      uxv = @am_manager.find_all_samant_resources(["Uxv"], {hasID: path_ary[path_ary.index{|item| item.downcase == "uxv-" + method} + 1]})
      speed = path_ary[path_ary.index{|item| item.downcase == "speed"} + 1].to_i
      sensor_ary = path_ary[(path_ary.index{|item| item.downcase == "sensor"} + 1)]
                           .split(",")
                           .map {|sensorId| @am_manager.find_all_samant_resources(["SensingDevice"], {hasID: sensorId})}
                           .flatten unless !path_ary.index{|item| item.downcase == "sensor"}
      sensor_ary = [] if sensor_ary == nil
      netIfc_ary = path_ary[(path_ary.index{|item| item.downcase == "netifc"} + 1)]
                        .split(",")
                        .map {|netifcId| @am_manager.find_all_samant_resources(["WiredInterface"], {hasID: netifcId}) + @am_manager.find_all_samant_resources(["WirelessInterface"], {hasID: netifcId})}
                        .flatten unless !path_ary.index{|item| item.downcase == "netifc"}
      netIfc_ary = [] if netIfc_ary == nil

      # debug uxv.inspect + " " + speed.to_s + " " + sensor_ary.inspect + " " + netIfc_ary.inspect

      # Validate if uxv actually exists

      if uxv.empty?
        @return_struct[:code][:geni_code] = 7 # operation refused
        @return_struct[:output] = "UxV doesn't exist. Please use the List Resources call to check the available resources."
        @return_struct[:value] = ''
        return ['application/json', JSON.pretty_generate(@return_struct)]
      else
        uxv = uxv.first
      end

      # Validate if speed is within limits

      if speed > uxv.hasTopSpeed.to_i
        @return_struct[:code][:geni_code] = 7 # operation refused
        @return_struct[:output] = "This UxV's top speed is :" + uxv.hasTopSpeed
        @return_struct[:value] = ''
        return ['application/json', JSON.pretty_generate(@return_struct)]
      end

      # Validate if sensors and interfaces actually exist in given uxv

      debug "UxV subsystem " + uxv.hasSensorSystem.hasSubSystem.inspect
      unless (sensor_ary.map{|sensor| sensor.uri} - uxv.hasSensorSystem.hasSubSystem.map{|sensor| sensor.uri}).empty? && (netIfc_ary.map{|ifc| ifc.uri} - uxv.hasInterface.map{|ifc| ifc.uri}).empty?
        @return_struct[:code][:geni_code] = 7 # operation refused
        @return_struct[:output] = "Some or all of the given Sensors or Network Interfaces are not compatible with the given UxV. Please use the List Resources call to check the compatibility again."
        @return_struct[:value] = ''
        return ['application/json', JSON.pretty_generate(@return_struct)]
      end

      sensor_consumption = 0
      netIfc_consumption = 0
      sensor_ary.map { |sensor|
        sensor_consumption += sensor.consumesPower.to_i
      }
      debug "Total Sensors' consumption: " + sensor_consumption.to_s + "W"
      netIfc_ary.map { |netIfc|
        netIfc_consumption += netIfc.consumesPower.to_i
      }
      debug "Total Interfaces' consumption: " + netIfc_consumption.to_s + "W"
      consumption = uxv.consumesPower.to_i*(speed/uxv.hasAvgSpeed.to_i.to_f) + sensor_consumption + netIfc_consumption
      debug "Total UxV's consumption: " + consumption.to_s + "W"
      endurance = uxv.battery.to_i/consumption

      distance = endurance*speed

      # Compute the total time duration (in seconds) of a specific node travelling with the specified average speed / sensors / network interfaces, using the given model
      endurance = (endurance.round(2)*60).to_s + " minutes"
      debug "Endurance:" + endurance.to_s

      # Compute the total distance (in meters) that a specified node can cover, having the given average speed, using the given model and based on the node's battery life
      distance = (distance.round(2)).to_s + " km"
      debug "Distance:" + distance.to_s

      @return_struct[:code][:geni_code] = 0
      @return_struct[:value] = eval(method)
      @return_struct[:output] = ''
      return ['application/json', JSON.pretty_generate(@return_struct)]

    end

    def uxv(options)
      path = options[:req].env["REQUEST_PATH"]

      # Transform path to resources

      path_ary = Pathname(path).each_filename.to_a
      # TODO consider changing :resourceId to :hasID *generally*
      uxv = @am_manager.find_all_samant_resources(["Uxv"], {hasID: path_ary[path_ary.index{|item| item.downcase == "uxv"} + 1]}).first
      if path_ary.index{|item| item.downcase == "sensor"}
        res = uxv.hasSensorSystem.hasSubSystem.map{|sensor| sensor.observes.map{|phenomena| phenomena.uri.to_s.split("#").last.chop}}.flatten
      elsif path_ary.index{|item| item.downcase == "sensortype"}
        sensorType = path_ary[path_ary.index{|item| item.downcase == "sensortype"} + 1]
        res = uxv.hasSensorSystem.hasSubSystem.map{|sensor| sensor.observes.map{|phenomena| phenomena.uri.to_s.split("#").last.chop.downcase}}.flatten.include? sensorType.downcase
      elsif path_ary.index{|item| item.downcase == "netifc"}
        res = uxv.hasInterface.map{|ifc| ifc.hasInterfaceType}.compact
      elsif path_ary.index{|item| item.downcase == "netifctype"}
        netifcType = path_ary[path_ary.index{|item| item.downcase == "netifctype"} + 1]
        res = uxv.hasInterface.map{|ifc| ifc.hasInterfaceType.downcase }.compact.include? netifcType.downcase
      else
        @return_struct[:code][:geni_code] = 7 # operation refused
        @return_struct[:output] = "Unknown operation requested. Please try again."
        @return_struct[:value] = ''
        return ['application/json', JSON.pretty_generate(@return_struct)]
      end

      @return_struct[:code][:geni_code] = 0
      @return_struct[:value] = res
      @return_struct[:output] = ''
      return ['application/json', JSON.pretty_generate(@return_struct)]

    end

  end
end