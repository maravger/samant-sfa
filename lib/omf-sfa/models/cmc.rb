require 'omf-sfa/models/component'
require 'omf-sfa/models/node'
require 'omf-sfa/models/e_node_b'
require 'omf-sfa/models/ip'

module OMF::SFA::Model
  class Cmc < Component

    one_to_one :node
    one_to_one :e_node_b
    many_to_one :ip

    plugin :nested_attributes
    nested_attributes :node, :e_node_b, :ip

    def self.exclude_from_json
      sup = super
      [:ip_id].concat(sup)
    end

    def to_hash_brief
      values[:ip] = self.ip.to_hash_brief
      super
    end

    def self.include_nested_attributes_to_json
      sup = super
      [:ip].concat(sup)
    end
  end
end
