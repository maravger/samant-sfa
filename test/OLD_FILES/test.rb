require 'rubygems'
require 'dm-core'


DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, :adapter => :in_memory)
#DataMapper.setup(:default, :adapter => 'yaml', :path => '/tmp/test_yaml')

# DataMapper::Model.append_extensions(Pagination::ClassMethods)
# DataMapper::Model.append_inclusions(Pagination::InstanceMethods)

require 'omf-sfa/resource'
include OMF::SFA::Resource

DataMapper.finalize



#include OMF::SFA::Resource

# GURN.default_prefix = "urn:publicid:IDN+mytestbed.net"
# Component.default_domain = "norbit.nicta.com.au"
# Component.default_component_manager_id = "authority+am"

def create_node()
  n = OMF::SFA::Resource::Node.create(#:component_name => 'foo'
    :name => 'foo' # GURN.sfa_create('foo', n)
  )
end

def create_link()
  l = Link.create()
  
  n = Node.first  
  i1 = Interface.create(:node => n, :network => l)
  i2 = Interface.create(:node => n, :network => l)
  l
end

def create_network()
  nw = Network.create()
  
  n = Node.first
  i1 = Interface.create(:node => n, :network => nw)
  i2 = Interface.create(:node => n, :network => nw)
  i3 = Interface.create(:node => n, :network => nw)  
  nw
end

create_node
create_link
#create_network

n = Node.first

#puts (n.methods - Object.new.methods).sort.inspect
#puts Interface.first.node.inspect

i = Interface.first
#puts i
#puts Component.sfa_advertisement_xml([i])
#puts Node.first.interfaces
puts Component.sfa_advertisement_xml([Node.all, Network.all])

#puts Component.all
#puts Node.first.interfaces

