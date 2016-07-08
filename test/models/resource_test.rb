require 'rubygems'
gem 'minitest' # ensures you are using the gem, not the built in MT
require 'minitest/autorun'
require 'minitest/pride'
require 'sequel'

db = Sequel.sqlite # In Memory database
Sequel.extension :migration
Sequel::Migrator.run(db, "./migrations") # Migrating to latest
require 'omf-sfa/models'

# Must use this class as the base class for your tests
class Resource < MiniTest::Test
  def run(*args, &block)
    result = nil
    Sequel::Model.db.transaction(:rollback=>:always, :auto_savepoint=>true){result = super}
    result
  end

  def test_that_can_create_a_resource
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    assert_instance_of OMF::SFA::Model::Resource, res
  end

  def test_that_on_create_it_will_generate_urn
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    refute_nil res.urn
  end

  def test_that_on_create_it_will_generate_uuid
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    refute_nil res.uuid
  end

  def test_that_can_delete_a_resource
    OMF::SFA::Model::Resource.create(name: 'resource1')
    res = OMF::SFA::Model::Resource.first(name: 'resource1')
    refute_nil res.destroy
  end

  def test_that_can_add_an_account
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    account = OMF::SFA::Model::Account.create(name: 'account1')
    res.account = account
    assert_same account, res.account
  end

  def test_that_to_json_wont_include_nil_values
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    JSON.parse(res.to_json).each do |k,v|
      refute_nil v
    end
  end

  def test_that_to_hash_wont_include_nil_values
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    res.to_hash.each do |k,v|      
      refute_nil v
    end
  end

  def test_that_to_hash_will_include_associations
    res = OMF::SFA::Model::Resource.create(name: 'resource1')
    account = OMF::SFA::Model::Account.create(name: 'account1')
    res.account = account

    assert_equal '{"id":1,"account_id":2,"name":"resource1","urn":"urn:publicid:IDN+domain+resource+resource1","type":"OMF::SFA::Model::Resource","account":{"name":"account1"}}', res.to_json(:include=>{:account => {:only => :name}}, :except => [:uuid])
  end

  def test_that_a_resource_can_be_cloned
    res = OMF::SFA::Model::Resource.create(name: 'resource1')

    clone = res.clone
    reses = OMF::SFA::Model::Resource.all

    assert_equal reses.count, 2
    assert_equal clone.name, res.name
    refute_equal clone.uuid, res.uuid
  end
end # Class Resource

