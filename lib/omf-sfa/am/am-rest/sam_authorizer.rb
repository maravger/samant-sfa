# require 'omf_common/lobject'
require 'omf-sfa/am/default_authorizer'
require 'omf-sfa/am/user_credential'
# require 'omf-sfa/am/privilege_credential'

module OMF::SFA::AM::Rest

  include OMF::Common

  # This class implements the decision logic for determining
  # access of a user in a specific context to specific functionality
  # in the AM
  #
  class SAMAuthorizer < OMF::SFA::AM::DefaultAuthorizer

    # @!attribute [r] account
    #        @return [Account] The account associated with this instance
    attr_reader :account

    # @!attribute [r] project
    #        @return [OProject] The project associated with this account
    attr_reader :project

    # @!attribute [r] user
    #        @return [User] The user associated with this membership
    attr_reader :user


    def self.create_for_rest_request(authenticated, certificate, account, am_manager, credentials = nil)

      if authenticated
        raise OMF::SFA::AM::InsufficientPrivilegesException.new("Missing peer cert") unless certificate
        peer = OMF::SFA::AM::UserCredential.unmarshall(certificate)
        
        debug "Requester: #{peer.subject} :: #{peer.user_urn}"

        unless peer.valid_at?
          OMF::SFA::AM::InsufficientPrivilegesException.new "The certificate has expired or not valid yet. Check the dates."
        end

        user_descr = {}
        user_descr.merge!({uuid: peer.user_uuid}) unless peer.user_uuid.nil?
        user_descr.merge!({urn: peer.user_urn}) unless peer.user_urn.nil?
        raise OMF::SFA::AM::InsufficientPrivilegesException.new "URN and UUID are missing." if user_descr.empty?

        begin
          #user = am_manager.find_user(user_descr) !!! CHANGED
          user = am_manager.find_or_create_user(user_descr)
        rescue OMF::SFA::AM::UnavailableResourceException
          raise OMF::SFA::AM::InsufficientPrivilegesException.new "User: '#{user_descr}' does not exist"
        end

        if credentials['expires']

        self.new(account, peer, user, am_manager, credentials)
      else
        self.new(nil, nil, nil, am_manager, credentials)
        end
      end
    end

    ##### ACCOUNT

    def can_view_account?(account)
      debug "Check permission 'can_view_account?' (#{account == @account}, #{@permissions[:can_view_account?]})"

      unless @permissions[:can_view_account?]
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end

      return true if @user.nil? && @account.nil?

      return true if @account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)

      @user.get_all_accounts.each do |acc|
        return true if acc == account
      end
      raise OMF::SFA::AM::InsufficientPrivilegesException.new
    end

    def can_renew_account?(account, expiration_time)
      debug "Check permission 'can_renew_account?' (#{account == @account}, #{@permissions[:can_renew_account?]})"
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (account == @account && @permissions[:can_renew_account?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    def can_close_account?(account)
      debug "Check permission 'can_close_account?' (#{account == @account}, #{@permissions[:can_close_account?]})"
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (account == @account && @permissions[:can_close_account?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    ##### RESOURCE

    def can_create_resource?(resource, type)
      type = type.downcase
      debug "Check permission 'can_create_resource?' (#{type == 'lease'}, #{@permissions[:can_create_resource?]})"
      #debug "AKAOUNT " + @account.inspect
      #debug "GIOUZER " + @user.inspect
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (type == 'lease' && @permissions[:can_create_resource?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    def can_create_samant_resource?(resource, type)
      debug "Check permission (#{@permissions.inspect})"
      unless @permissions[:can_create_resource?]
        raise InsufficientPrivilegesException.new
      end
      true
    end

    def can_release_samant_resource?(resource)
      debug "Check permission (#{@permissions.inspect})"
      debug "slice urn = " + resource.hasSliceID.inspect
      debug "account urn = " + @account.urn.inspect

      # TODO FIX THIS: user accounts cannot release resources!!!!
      unless resource.hasSliceID == @account.id && @permissions[:can_release_resource?]
        #raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    ##### LEASE

    def can_modify_lease?(lease)
      debug "Check permission 'can_modify_lease?' (#{@account == lease.account}, #{@permissions[:can_modify_lease?]})"
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (@account == lease.account && @permissions[:can_modify_lease?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    def can_modify_samant_lease?(lease)
      # debug "account: " + @account[:urn].inspect
      # debug "lease account: " + lease.hasSliceID.inspect
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (@account[:urn] == lease.hasSliceID && @permissions[:can_modify_lease?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    def can_release_lease?(lease)
      debug "Check permission 'can_release_lease?' (#{@account == lease.account}, #{@permissions[:can_release_lease?]})"
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (@account == lease.account && @permissions[:can_release_lease?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

    def can_release_samant_lease?(lease)
      debug "account: " + @account[:urn].inspect
      debug "lease account: " + lease.hasSliceID.inspect
      unless (@account == @am_manager._get_nil_account || @user.has_nil_account?(@am_manager)) || (@account[:urn] == lease.hasSliceID && @permissions[:can_release_lease?])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new
      end
      true
    end

      protected

    def initialize(account, user_cert, user, am_manager, credentials)
      debug "Initialize for account: #{account} and user: #{user.inspect})"
      super()
      @am_manager = am_manager
      @user_cred = credentials

      unless (user_cert.user_urn == credentials['user']['name'])
        raise OMF::SFA::AM::InsufficientPrivilegesException.new "User urn mismatch in certificate and credentials. cert:'#{user_cert.user_urn}' cred:'#{credentials['user']['name']}'"
      end

      # TODO check how to create real permissions
      @permissions = {
          can_create_account?:   true,
          can_view_account?:     true,
          can_renew_account?:    true,
          can_close_account?:    true,
          # RESOURCE
          can_create_resource?:  true,
          can_modify_resource?:  true,
          can_view_resource?:    true,
          can_release_resource?: true,
          # LEASE
          can_view_lease?:       true,
          can_modify_lease?:     true,
          can_release_lease?:    true
      }
      debug "SAMANT REST permissions" + @permissions.inspect

      # @account = OMF::SFA::Model::Account.first({name: account}) if account
      # @account = @user.accounts.first if @account.nil?

      acc_name = create_account_name_from_urn(account)

      @account = am_manager.find_or_create_account({:urn => account, :name => acc_name}, self)
      @user = user
      debug "Account " + @account.inspect
      debug "Renewing account '#{@account.name}' until '#{@user_cred['expires']}'"
      am_manager.renew_account_until(@account, @user_cred['expires'], self)

      # TODO check for real privileges

      if @account.closed?
        if @permissions[:can_create_account?]
          @account.closed_at = nil
        else
          raise OMF::SFA::AM::InsufficientPrivilegesException.new("You don't have the privilege to enable a closed account")
        end
      end
      @account.add_user(@user) unless @account.users.include?(@user)
      @account.save
    end


    def create_account_name_from_urn(urn)
      max_size = 32
      gurn = OMF::SFA::Model::GURN.create(urn, :type => "OMF::SFA::Resource::Account")
      domain = gurn.domain.gsub(":", '.')
      acc_name = "#{domain}.#{gurn.short_name}"
      return acc_name if acc_name.size <= max_size

      domain = gurn.domain
      authority = domain.split(":").first.split(".").first
      subauthority = domain.split(":").last
      acc_name = "#{authority}.#{subauthority}.#{gurn.short_name}"
      return acc_name if acc_name.size <= max_size

      acc_name = "#{subauthority}.#{gurn.short_name}"
      if acc_name.size <= max_size
        if account_name_exists_for_another_urn?(acc_name, urn)
          nof_chars_to_delete = "#{authority}.#{subauthority}.#{gurn.short_name}".size - max_size
          acc_name = ""
          acc_name += "#{authority[0..-(nof_chars_to_delete / 2 + 1).to_i]}." # +1 for the dot in the end
          acc_name +=  "#{subauthority[0..-(nof_chars_to_delete / 2 + 1).to_i]}.#{gurn.short_name}"
          acc_name = acc_name.sub('..','.')
          return acc_name unless account_name_exists_for_another_urn?(acc_name, urn)
        else
          return acc_name
        end
      end

      acc_name = gurn.short_name
      return acc_name if acc_name.size <= max_size && !account_name_exists_for_another_urn?(acc_name, urn)
      raise OMF::SFA::AM::FormatException.new "Slice urn is too long, account '#{acc_name}' cannot be generated."
    end

    def account_name_exists_for_another_urn?(name, urn)
      acc = OMF::SFA::Model::Account.first(name: name)
      return true if acc && acc.urn != urn
      false
    end

  end # class
end # module
