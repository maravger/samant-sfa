
require 'omf-sfa/resource/ocomponent'
require 'omf-sfa/resource/interface'
require 'omf-sfa/resource/sliver_type'

module OMF::SFA::Resource

  class Node < OComponent

    oproperty :hardware_type, String, :required => false
    oproperty :sliver_type, :SliverType, :required => false
    oproperty :interfaces, :Interface, :functional => false
    oproperty :exclusive, String, :default => true
    oproperty :disk, String
    oproperty :hostname, String
    oproperty :cmc, :ChasisManagerCard
    oproperty :cpu, :Cpu
    oproperty :ram, String
    oproperty :ram_type, String
    oproperty :hd_capacity, String
    oproperty :available_cpu, Integer, :required => false # percentage of available cpu
    oproperty :available_ram, Integer, :required => false # percentage of available ram
    oproperty :location, :Location
    oproperty :boot_state, String
    #belongs_to :sliver

    sfa_class 'node'
    sfa :hardware_type, :attr_value => 'name'
    sfa :available, :attr_value => 'now'  # <available now="true">
    sfa :sliver_type, :inline => true
    sfa :interfaces, :inline => true, :has_many => true
    #sfa :client_id, :attribute => true
    sfa :exclusive, :attribute => true
    sfa :location, :inline => true
    sfa :boot_state, :attribute => true


    # Override xml serialization of 'interface'
    #def _to_sfa_property_xml(pname, value, res_el, pdef, obj2id, opts)
    #  if pname == 'interfaces'
    #    value.each do |iface|
    #      iface.to_sfa_ref_xml(res_el, obj2id, opts)
    #    end
    #    return
    #  end
    #  super
    #end

    def _from_sfa_interfaces_property_xml(resource_el, props)
      resource_el.children.each do |el|
        next unless el.is_a? Nokogiri::XML::Element
        next unless el.name == 'interface' # should check namespace as well
        interface = OMF::SFA::Resource::OComponent.from_sfa(el)
        #puts "INTERFACE '#{interface}'"
        self.interfaces << interface
      end
    end

    def xx_to_sfa_interfaces_property_hash(interfaces, pdef, href2obj, opts)
      # opts = opts.dup
      # opts[:href_prefix] = (opts[:href_prefix] || '/') + 'interfaces/'
      #interfaces.collect do |o|
      interfaces.map do |o|
        puts "INTERFACE: #{o}"
        #o.to_sfa_hash(href2obj, opts)
        'hi'
      end
    end

    #before :save do
    #  resource_type = 'node'
    #  super
    #end

  end

end # OMF::SFA

