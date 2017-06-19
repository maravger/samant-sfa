require 'rubygems'
gem 'minitest' # ensures you're using the gem, and not the built in MT
require 'minitest/autorun'
require 'minitest/pride'
require 'omf-sfa/am/am_manager'
require 'dm-migrations'
require 'omf_common/load_yaml'
require 'active_support/inflector'

include OMF::SFA::AM

def init_dm
  # setup database
  DataMapper::Logger.new($stdout, :info)

  DataMapper.setup(:default, 'sqlite::memory:')
  #DataMapper.setup(:default, 'sqlite:///tmp/am_test.db')
  DataMapper::Model.raise_on_save_failure = true
  DataMapper.finalize

  DataMapper.auto_migrate!
end

def init_logger
  OMF::Common::Loggable.init_log 'am_manager', :searchPath => File.join(File.dirname(__FILE__), 'am_manager')
  @config = OMF::Common::YAML.load('omf-sfa-am', :path => [File.dirname(__FILE__) + '/../../etc/omf-sfa'])[:omf_sfa_am]
end

describe AMManager do

  init_logger

  init_dm

  before do
    DataMapper.auto_migrate! # reset database
  end

  let (:scheduler) do
    scheduler = Class.new do
      def self.get_nil_account
        nil
      end
      def self.create_resource(resource_descr, type_to_create, oproperties, auth)
        resource_descr[:resource_type] = type_to_create
        resource_descr[:account] = auth.account
        type = type_to_create.camelize
        resource = eval("OMF::SFA::Resource::#{type}").create(resource_descr)
        if type_to_create.eql?('Lease')
          resource.valid_from = oproperties[:valid_from]
          resource.valid_until = oproperties[:valid_until]
          resource.save
        end
        return resource
      end
      def self.release_resource(resource, authorizer)
        resource.destroy
      end
    end
    scheduler
  end

  let (:manager) { AMManager.new(scheduler) }

  describe 'instance' do
    it 'can create an AM Manager' do
      manager
    end

    it 'can manage a resource' do
      r = OMF::SFA::Resource::OResource.create(:name => 'r')
      manager.manage_resource(r)
    end
  end

  describe 'account' do

    before do
      @auth = MiniTest::Mock.new
      DataMapper.auto_migrate! # reset database
    end

    it 'can create account' do
      @auth.expect(:can_create_account?, true)

      manager.liaison = MiniTest::Mock.new
      manager.liaison.expect(:create_account, true, [OMF::SFA::Resource::Account])

      account = manager.find_or_create_account({:name => 'a'}, @auth)
      account.must_be_instance_of(OMF::SFA::Resource::Account)

      manager.liaison.verify
      @auth.verify
    end

    it 'can find created account' do
      a1 = OMF::SFA::Resource::Account.create(name: 'a')

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      a2 = manager.find_or_create_account({:name => 'a'}, @auth)
      a1.must_equal a2

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      a3 = manager.find_account({:name => 'a'}, @auth)
      a1.must_equal a3

      @auth.verify
    end

    it 'throws exception when looking for non-exisiting account' do
      lambda do
        manager.find_account({:name => 'a'}, @auth)
      end.must_raise(UnavailableResourceException)
    end

    it 'can request all accounts visible to a user' do
      manager.find_all_accounts(@auth).must_be_empty

      a1 = OMF::SFA::Resource::Account.create(name: 'a1')

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      manager.find_all_accounts(@auth).must_equal [a1]

      a2 = OMF::SFA::Resource::Account.create(name: 'a2')

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])

      manager.find_all_accounts(@auth).must_equal [a1, a2]

      @auth.verify

      def @auth.can_view_account?(account)
        raise InsufficientPrivilegesException
      end
      manager.find_all_accounts(@auth).must_be_empty
    end

    it 'can request accounts which are active' do
      a1 = OMF::SFA::Resource::Account.create(name: 'a1')

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      a2 = manager.find_active_account({:name => 'a1'}, @auth)
      a2.wont_be_nil

      # Expire account
      a2.valid_until = Time.now - 100
      a2.save
      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      lambda do
        manager.find_active_account({:name => 'a1'}, @auth)
      end.must_raise(UnavailableResourceException)

      @auth.verify
    end

    it 'can renew accounts' do
      a1 = OMF::SFA::Resource::Account.create(name: 'a1')

      time = Time.now + 100
      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      @auth.expect(:can_renew_account?, true, [a1, time])
      a2 = manager.renew_account_until({:name => 'a1'}, time, @auth)

      # we convert the time to INT in order to round up fractional seconds
      # more info: http://stackoverflow.com/questions/8763050/how-to-compare-time-in-ruby
      time1 = Time.at(a2.valid_until.to_i)
      time2 = Time.at(time.to_i)
      time1.must_equal time2

      @auth.verify
    end

    it 'can close account and release its resources' do
      manager.liaison = MiniTest::Mock.new

      a1 = OMF::SFA::Resource::Account.create(name: 'a1')

      OMF::SFA::Resource::Node.create(account: a1)

      @auth.expect(:can_view_account?, true, [OMF::SFA::Resource::Account])
      @auth.expect(:can_close_account?, true, [a1])

      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::Node])

      @auth.expect(:can_release_resource?, true, [OMF::SFA::Resource::Node])
      manager.liaison.expect(:close_account, true, [a1])
      a2 = manager.close_account({:name => 'a1'}, @auth)
      a2.reload
      a2.active?.must_equal false
      a2.closed?.must_equal true

      OMF::SFA::Resource::Node.first(account: a1).must_be_nil

      manager.liaison.verify
      @auth.verify
    end
  end #account

  describe 'users' do

    before do
      DataMapper.auto_migrate! # reset database
    end

    it 'can create a user' do
      u = manager.find_or_create_user({:urn => 'urn:publicid:IDN+topdomain:subdomain+user+pi'}, [])
      u.must_be_instance_of(OMF::SFA::Resource::User)
    end

    it 'can find an already created user' do
      user_descr = {:name => 'pi'}
      u1 = OMF::SFA::Resource::User.create(user_descr)
      u2 = manager.find_or_create_user(user_descr, [])
      u1.must_equal u2

      u2 = manager.find_user(user_descr)
      u1.must_equal u2
    end

    it 'throws an exception when looking for a non existing user' do
      lambda do
        manager.find_user({:urn => 'urn:publicid:IDN+topdomain:subdomain+user+pi'})
      end.must_raise(UnavailableResourceException)
    end

  end #users

  describe 'lease' do

    lease_oproperties = {:valid_from => Time.now, :valid_until => Time.now + 100}

    before do
      @auth = MiniTest::Mock.new
      DataMapper.auto_migrate! # reset database
      @account = OMF::SFA::Resource::Account.first_or_create(:name => 'a1')
    end

    it 'can create lease' do
      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      @auth.expect(:account, @account)
      lease = manager.find_or_create_lease({:name => 'l1'}, lease_oproperties, @auth)
      lease.must_be_instance_of(OMF::SFA::Resource::Lease)

      @auth.verify
    end

    it 'can find created lease' do
      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      @auth.expect(:account, @account)
      a1 = manager.find_or_create_lease({:name => 'l1'}, lease_oproperties, @auth)

      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      a2 = manager.find_or_create_lease({:name => 'l1'}, lease_oproperties, @auth)
      a1.must_equal a2

      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      a3 = manager.find_lease({:name => 'l1'}, {}, @auth)
      a1.must_equal a3

      @auth.verify
    end

    it 'throws exception when looking for non-exisiting lease' do
      lambda do
        manager.find_lease({:name => 'l1'}, {}, @auth)
      end.must_raise(UnavailableResourceException)
    end

    it "can request all user's leases" do
      OMF::SFA::Resource::Lease.create({:name => "another_user's_lease"})

      @auth.expect(:can_view_account?, true, [@account])
      a1 = manager.find_or_create_account({:name => 'a1'}, @auth)

      @auth.expect(:account, a1)

      manager.find_all_leases(a1, @auth).must_be_empty

      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      l1 = manager.find_or_create_lease({:name => 'l1', :account => a1}, lease_oproperties, @auth)

      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      manager.find_all_leases(a1, @auth).must_equal [l1]

      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      @auth.expect(:account, a1)
      l2 = manager.find_or_create_lease({:name => 'l2', :account => a1}, lease_oproperties, @auth)

      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      manager.find_all_leases(a1, @auth).must_equal [l1, l2]

      def @auth.can_view_lease?(lease)
        raise InsufficientPrivilegesException
      end
      manager.find_all_leases(a1, @auth).must_be_empty

      @auth.verify
    end

    it 'can modify leases' do
      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      @auth.expect(:account, @account)
      l1 = manager.find_or_create_lease({:name => 'l1'}, lease_oproperties, @auth)
      @auth.verify

      valid_from = Time.now + 1000
      valid_until = valid_from + 1000
      @auth.expect(:can_modify_lease?, true, [l1])
      l2 = manager.modify_lease({:valid_from => valid_from, :valid_until => valid_until}, l1, @auth)

      l2.must_equal l1.reload

      # more info on comparing time objects here: http://stackoverflow.com/questions/8763050/how-to-compare-time-in-ruby
      time1 = Time.at(l2.valid_from.to_i)
      time1.must_equal Time.at(valid_from.to_i)

      time1 = Time.at(l2.valid_until.to_i)
      time1.must_equal Time.at(valid_until.to_i)

      @auth.verify
    end

    it 'can release a lease' do
      @auth.expect(:can_create_resource?, true, [Hash, 'Lease'])
      @auth.expect(:account, @account)
      l1 = manager.find_or_create_lease({:name => 'l1'}, lease_oproperties, @auth)

      @auth.expect(:can_release_lease?, true, [l1])
      manager.release_lease(l1, @auth)

      l1.reload
      l1.cancelled?.must_equal true

      @auth.verify
    end

    it 'can find all leases' do
      OMF::SFA::Resource::Lease.create({:name => "lease_name"})

      @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease])
      r = manager.find_all_leases(@auth)

      r.first.must_be_instance_of(OMF::SFA::Resource::Lease)
      r.first.name.must_equal("lease_name")

      @auth.verify
    end

    it 'can find leases based on their status' do
      l1 = OMF::SFA::Resource::Lease.create({:name => "lease1", :status => "past"})
      l2 = OMF::SFA::Resource::Lease.create({:name => "lease2", :status => "pending"})
      l3 = OMF::SFA::Resource::Lease.create({:name => "lease3", :status => "accepted"})
      l4 = OMF::SFA::Resource::Lease.create({:name => "lease4", :status => "cancelled"})
      l5 = OMF::SFA::Resource::Lease.create({:name => "lease5", :status => "active"})

      3.times { @auth.expect(:can_view_lease?, true, [OMF::SFA::Resource::Lease]) }
      r = manager.find_all_leases(nil, ["pending", "accepted", "active"], @auth)

      r.must_include(l2)
      r.must_include(l3)
      r.must_include(l5)

      @auth.verify
    end

  end #lease

  describe 'resource' do

    before do
      @auth = Minitest::Mock.new
      DataMapper.auto_migrate! # reset database
      @account = OMF::SFA::Resource::Account.create(:name => 'a')
    end

    it 'finds single resource belonging to anyone through its name (Hash)' do
      r1 = OMF::SFA::Resource::OResource.create(:name => 'r1')
      manager.manage_resources([r1])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_resource({:name => 'r1'}, @auth)
      r.must_be_instance_of(OMF::SFA::Resource::OResource)

      @auth.verify
    end

    it 'finds single resource belonging to anyone through its name (String)' do
      r1 = OMF::SFA::Resource::OResource.create(:name =>'r1')
      manager.manage_resources([r1])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_resource('r1', @auth)
      r.must_be_instance_of(OMF::SFA::Resource::OResource)

      @auth.verify
    end

    it 'finds a resource through its instance' do
      r1 = OMF::SFA::Resource::Node.create(:name => 'r1')
      manager.manage_resources([r1])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::Node])
      r = manager.find_resource(r1, @auth)
      r.must_be_instance_of(OMF::SFA::Resource::Node)

      @auth.verify
    end

    it 'finds a resource through its uuid' do
      r1 = OMF::SFA::Resource::OResource.create(:uuid => '759ae077-2fda-4d02-8921-ab0235a09920')
      manager.manage_resources([r1])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_resource('759ae077-2fda-4d02-8921-ab0235a09920', @auth)
      r.must_be_instance_of(OMF::SFA::Resource::OResource)

      @auth.verify
    end

    it 'throws an exception for unknown resource description' do
      lambda do
        manager.find_resource(nil, @auth)
      end.must_raise(FormatException)
    end

    it 'throws an exception when looking for a non existing resource' do
      lambda do
        manager.find_resource('r1', @auth)
      end.must_raise(UnknownResourceException)
    end

    it 'throws an exception when is not privileged to view the resource' do
      authorizerr = Minitest::Mock.new
      r1 = OMF::SFA::Resource::OResource.create(:name =>'r1')
      manager.manage_resources([r1])

      def authorizerr.can_view_resource?(*args)
        raise InsufficientPrivilegesException.new
      end

      lambda do
        manager.find_resource('r1', authorizerr)
      end.must_raise(InsufficientPrivilegesException)
    end

    it 'finds single resource belonging to an account' do
      r1 = OMF::SFA::Resource::OResource.create(:name => 'r1')
      manager.manage_resources([r1])

      @auth.expect(:account, @account)
      lambda do
        manager.find_resource_for_account({:name => 'r1'}, @auth)
      end.must_raise(UnknownResourceException)

      # now, assign it to this account
      r1.account = @account
      r1.save
      @auth.expect(:account, @account)
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_resource_for_account({:name => 'r1'}, @auth)
      r.must_equal r1

      @auth.verify
    end

    it 'will find all the resources of an account' do
      r1 = OMF::SFA::Resource::OResource.create({:name => 'r1', :account => @account})
      r2 = OMF::SFA::Resource::OResource.create({:name => 'r2', :account => @account})
      r3 = OMF::SFA::Resource::OResource.create({:name => 'r3'})

      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_all_resources_for_account(@account, @auth)
      r.must_equal [r1, r2]

      @auth.verify
    end

    it 'will find all the components of an account' do
      r1 = OMF::SFA::Resource::OComponent.create({:name => 'r1', :account => @account})
      r2 = OMF::SFA::Resource::Node.create({:name => 'r2', :account => @account})
      r3 = OMF::SFA::Resource::OResource.create({:name => 'r3', :account => @account})
      r4 = OMF::SFA::Resource::OComponent.create({:name => 'r4'})

      2.times {@auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])}
      r = manager.find_all_components_for_account(@account, @auth)
      r.must_equal [r1, r2]

      @auth.verify
    end

    it 'will create a resource' do
      resource_descr = {:name => 'r1'}
      type_to_create = 'node'
      @auth.expect(:account, @account)
      @auth.expect(:can_create_resource?, true, [Hash, String])
      r = manager.find_or_create_resource(resource_descr, type_to_create, {}, @auth)
      r.must_equal OMF::SFA::Resource::Node.first(:name => 'r1')

      @auth.verify
    end

    it 'will find an already created resource' do
      resource_descr = {:name => 'r1'}
      r1 = OMF::SFA::Resource::OResource.create(resource_descr)
      type_to_create = 'node'
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])
      r = manager.find_or_create_resource(resource_descr, type_to_create, {}, @auth)
      r.must_equal r1

      @auth.verify
    end

    it 'will find all available resources of a given type' do
      n1 = OMF::SFA::Resource::Node.create(name: 'n1')
      n2 = OMF::SFA::Resource::Node.create(name: 'n2')
      t1 = Time.now
      t2 = t1 + 3600
      2.times {@auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])}
      scheduler.define_singleton_method(:resource_available?) do |resource, valid_from, valid_until| 
        true
      end

      res = manager.find_all_available_resources({type: 'Node'}, {},  t1, t2, @auth)

      res.must_equal [n1,n2]

      @auth.verify
    end

    it 'will find all available resources using oproperties for query' do
      n1 = OMF::SFA::Resource::Node.create(name: 'n1', domain: "domainA")
      n2 = OMF::SFA::Resource::Node.create(name: 'n2', domain: "domainB")
      t1 = Time.now
      t2 = t1 + 3600
      2.times {@auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])}
      scheduler.define_singleton_method(:resource_available?) do |resource, valid_from, valid_until| 
        true
      end

      res = manager.find_all_available_resources({type: 'Node'}, {domain: 'domainA'}, t1, t2, @auth)

      res.must_equal [n1]

      @auth.verify
    end

    it 'will find all available resources using 2 oproperties for query' do
      n1 = OMF::SFA::Resource::Node.create(name: 'n1', domain: "domainA", exclusive: true)
      n2 = OMF::SFA::Resource::Node.create(name: 'n2', domain: "domainB", exclusive: false)
      t1 = Time.now
      t2 = t1 + 3600
      2.times {@auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OResource])}
      scheduler.define_singleton_method(:resource_available?) do |resource, valid_from, valid_until| 
        true
      end

      res = manager.find_all_available_resources({type: 'Node'}, {domain: 'domainA', exclusive: true}, t1, t2, @auth)

      res.must_equal [n1]

      @auth.verify
    end

    it 'throws an exception when there are no resources available when asked for all available resources' do
      lambda do
        res = manager.find_all_available_resources({type: 'Node'}, {}, Time.now, Time.now + 100, @auth)
      end.must_raise(UnavailableResourceException)
    end

    it 'throws an exception when there are no resources available for the given description and timeslot' do
      n1 = OMF::SFA::Resource::Node.create(name: 'n1', account: @account)
      t1 = Time.now
      t2 = t1 + 3600
      l1 = OMF::SFA::Resource::Lease.create(name: 'l1', account: @account, valid_from: t1, valid_until: t2)
      n1.leases << l1
      n1.save
      l1.components << n1
      l1.save
      
      # mock resource_available method of scheduler to always return false
      scheduler.define_singleton_method(:resource_available?) do |resource, valid_from, valid_until| 
        false
      end
      lambda do
        res = manager.find_all_available_resources({type: 'Node'}, {}, t1 + 10, t2 - 10, @auth)
      end.must_raise(UnavailableResourceException)

      @auth.verify
    end

    it 'will create a resource if not already available for the account' do
      2.times {@auth.expect(:account, @account)}
      @auth.expect(:can_create_resource?, true, [Hash, String])
      descr = {:name => 'v1'}
      r = manager.find_or_create_resource_for_account(descr, 'o_resource', {}, @auth)
      vr = OMF::SFA::Resource::OResource.first({:name => 'v1', :account => @account})
      r.must_equal vr

      @auth.verify
    end

    it 'will create resource from rspec' do
      rspec = %{
        <rspec xmlns="http://www.geni.net/resources/rspec/3" xmlns:omf="http://nitlab.inf.uth.gr/schema/sfa/rspec/1" type="request">
          <node component_id="urn:publicid:IDN+openlab+node+node1" component_name="node1" client_id="omf">
          </node>
        </rspec>
      }
      req = Nokogiri.XML(rspec)

      @auth.expect(:can_create_resource?, true, [Hash, String])
      2.times {@auth.expect(:account, @account)}
      r = manager.update_resources_from_rspec(req.root, false, @auth)
      r.first.must_equal OMF::SFA::Resource::Node.first(:name => 'node1')

      @auth.verify
    end

    it 'will release a resource' do
      r1 = OMF::SFA::Resource::OResource.create(:name => 'r1')
      manager.manage_resources([r1])
      @auth.expect(:can_release_resource?, true, [r1])

      manager.release_resource(r1, @auth)
      OMF::SFA::Resource::OResource.first(:name => 'r1').must_be_nil

      @auth.verify
    end

    it 'will release all components of an account' do
      OMF::SFA::Resource::OResource.create({:name => 'r1', :account => @account})
      OMF::SFA::Resource::Node.create({:name => 'n1', :account => @account})
      OMF::SFA::Resource::Node.create({:name => 'n2'})
      OMF::SFA::Resource::OComponent.create({:name => 'c1', :account => @account})

      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::Node])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::OComponent])

      @auth.expect(:can_release_resource?, true, [OMF::SFA::Resource::Node])
      @auth.expect(:can_release_resource?, true, [OMF::SFA::Resource::OComponent])

      manager.release_all_components_for_account(@account, @auth)

      OMF::SFA::Resource::OResource.first({:account => @account}).wont_be_nil
      OMF::SFA::Resource::Node.first({:account => @account}).must_be_nil
      OMF::SFA::Resource::OComponent.first({:account => @account}).must_be_nil
      OMF::SFA::Resource::Node.first({:name => 'n2'}).wont_be_nil

      @auth.verify
    end

    it 'will release all the resources of a specific account' do
      #OMF::SFA::Resource::OResource.create({name: 'r1', account: account})
      OMF::SFA::Resource::Node.create({name: 'n1', account: @account})
      OMF::SFA::Resource::Node.create({name: 'n2'})
      OMF::SFA::Resource::Lease.create({name: 'l1', account: @account})

      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::Node])
      @auth.expect(:can_view_resource?, true, [OMF::SFA::Resource::Lease])

      @auth.expect(:can_release_resource?, true, [OMF::SFA::Resource::Node])
      @auth.expect(:can_release_resource?, true, [OMF::SFA::Resource::Lease])

      manager.release_all_resources_for_account(@account, @auth)

      OMF::SFA::Resource::Node.first({:account => @account}).must_be_nil
      OMF::SFA::Resource::OComponent.first({:account => @account}).must_be_nil
      OMF::SFA::Resource::Lease.first(account: @account).must_be_nil

      OMF::SFA::Resource::Account.first(:name => 'a').wont_be_nil
      OMF::SFA::Resource::Node.first({:name => 'n2'}).wont_be_nil

      @auth.verify
    end
  end #resource

end
