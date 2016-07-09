module OMF::SFA::ServiceAPIv3
  Struct.new("MethodDescriptionV3", :rpc_name, :method_name, :opts)

  # This defines a method to declare the service methods and all their
  # parameters.
  #
  def declare(rpc_name, method_name, opts = {}, &block)
    @@declarations ||= {}
    m = (@@declarations[self] ||= [])
    m << Struct::MethodDescriptionV3.new(rpc_name.to_sym, method_name.to_sym, opts)
  end

  def api_description()
    @@declarations ||= {}
    @@declarations[self] || []
  end
end

module OMF::SFA::AM::RPC
  module V3; end
end

module OMF::SFA::AM::RPC::V3::AMServiceAPI
  extend OMF::SFA::ServiceAPIv3

  declare :GetVersion, :get_version, {
    :short => "",
    :params => {},
    :return => {
      :type => :hash,
      :description => %{
         Return the version of the GENI Aggregate API
         supported by this aggregate.
      },
      :params => [
        {
          :name => 'geni_api',
          :type => :integer,
          :descriptiosn => %{
            Indicating the revision of the Aggregate Manager API that
            an aggregate supports. The current version of the API
            is 1 (one).
          }
        }
      ]
    }
  }

  declare :ListResources, :list_resources, {
    :short => %{Return information about available resources
                or resources allocated to a slice.},
    :params => [
      {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must
          be valid for this operation (signed by a valid GENI certificate
          authority either directly or by chain, and not expired). Note that
          the semantics of this argument is not clear. Alternative
          interpretations might, for example, accumulate privileges from each
          valid credential to determine overall caller permissions.
        }
      }, {
        :name => 'options',
        :type  => :hash,
        :description => %{
          A hash containing members indicating the set of resources
          the caller is interested in or the format of the result. In addition
          to the members specified below, callers can pass additional members
          that specific aggregate manager implementations might honor. The
          prefix geni_ is reserved for members that are part of this API
          specification. Implementations should choose an appropriate prefix
          to avoid conflicts.

          The following members are available for use in the options
          parameter. All aggregate managers are required to implement these
          options.},
        :params => [
          {
            :name => 'geni_available',
            :type => :boolean,
            :description => %{
              A boolean value indicating whether the caller is
              interested in all resources or available resources. If this value
              is true, the result should contain only available resources. If
              this value is false both available and allocated resources should
              be returned. The Aggregate Manager is free to limit visibility of
              certain resources based on the credentials parameter.
            }
          }, {
            :name => 'geni_compressed',
            :type => :boolean,
            :description => %{
              A boolean value indicating whether the caller
              would like the result to be compressed. If the value is true, the
              returned resource list will be compressed according to RFC 1950.
            }
          }, {
            :name => 'geni_slice_urn',
            :type => :string,
            :description => %{
              A string indicating that the caller is interested
              in the set of resources allocated to the slice named by this
              URN. If no resources are allocated to the indicated slice by this
              aggregate, an empty RSPEC should be returned.            }
          }
        ]
      }
    ],
    :return => {
      :type => :hash,
      :description => %{
        For ListResources, value is an RSpec listing and describing resources
        at this aggregate. Depending on the arguments, this may be an advertisement
        RSpec showing all local resources, or one showing only available local resources,
        or a manifest RSpec of resources reserved for a particular slice.
      },
      :params => [
        {
          :name => 'code',
          :type => :hash,
          :description => %{
            A struct indicating the success or failure of this call at
            the Aggregate Manager. It consists of 1 required field and 2 optional fields.
          },
          :params => [
            {
              :name => 'geni_code',
              :type => :integer,
              :description => %{
                An integer supplying the GENI standard return code indicating
                the success or failure of this call. Error codes are standardized
                and defined in the attached XML document. Codes may be negative.
                A success return is defined as geni_code of 0.
              }
            }
          ]
        },
        {
          :name => 'value',
          :type => :text_xml,
          :description => %{
            For ListResources, value is an RSpec listing and describing resources at
            this aggregate. Depending on the arguments, this may be an advertisement
            RSpec showing all local resources, or one showing only available local
            resources, or a manifest RSpec of resources reserved for a particular slice.
          }
        }
      ]
    }
  }

  declare :Describe, :describe, {
    :short => %{Return information about resources allocated to a slice.},
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          An array of urns that need to be described. At least one urn must
          be valid for this operation.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must
          be valid for this operation (signed by a valid GENI certificate
          authority either directly or by chain, and not expired). Note that
          the semantics of this argument is not clear. Alternative
          interpretations might, for example, accumulate privileges from each
          valid credential to determine overall caller permissions.
        }
      }, {
        :name => 'options',
        :type  => :hash,
        :description => %{
          A hash containing members indicating the set of resources
          the caller is interested in or the format of the result. In addition
          to the members specified below, callers can pass additional members
          that specific aggregate manager implementations might honor. The
          prefix geni_ is reserved for members that are part of this API
          specification. Implementations should choose an appropriate prefix
          to avoid conflicts.

          The following members are available for use in the options
          parameter. All aggregate managers are required to implement these
          options.},
        :params => [
          {
            :name => 'geni_compressed',
            :type => :boolean,
            :description => %{
              A boolean value indicating whether the caller
              would like the result to be compressed. If the value is true, the
              returned resource list will be compressed according to RFC 1950.
            }
          }
        ]
      }
    ],
    :return => {
      :type => :hash,
      :description => %{
        For ListResources, value is an RSpec listing and describing resources
        at this aggregate. Depending on the arguments, this may be an advertisement
        RSpec showing all local resources, or one showing only available local resources,
        or a manifest RSpec of resources reserved for a particular slice.
      },
      :params => [
        {
          :name => 'code',
          :type => :hash,
          :description => %{
            A struct indicating the success or failure of this call at
            the Aggregate Manager. It consists of 1 required field and 2 optional fields.
          },
          :params => [
            {
              :name => 'geni_code',
              :type => :integer,
              :description => %{
                An integer supplying the GENI standard return code indicating
                the success or failure of this call. Error codes are standardized
                and defined in the attached XML document. Codes may be negative.
                A success return is defined as geni_code of 0.
              }
            }
          ]
        },
        {
          :name => 'value',
          :type => :text_xml,
          :description => %{
            For ListResources, value is an RSpec listing and describing resources at
            this aggregate. Depending on the arguments, this may be an advertisement
            RSpec showing all local resources, or one showing only available local
            resources, or a manifest RSpec of resources reserved for a particular slice.
          }
        }
      ]
    }
  }

  declare :Allocate, :allocate, {
    :description => %{
      Allocate resources as described in a request RSpec argument to a slice with the 
      named URN. On success, one or more slivers are allocated, containing resources 
      satisfying the request, and assigned to the given slice. Allocated slivers are 
      held for an aggregate-determined period.
    },
    :params => [
      {
        :name => 'slice_urn',
        :type => :string_urn,
        :description  => %{
          The URN of the slice to which the resources specified in
          rspec will be allocated.
        }
      },
      {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions. Aggregates should
          ensure that the expiration time of the slice does not exceed
          the expiration time of the slice credential used to perform
          this operation.
        }
      }, {
        :name => 'rspec',
        :type => :text_xml,
        :description  => %{
          An RSPEC containing the resources that the caller is
          requesting for allocation to the slice specified in
          slice_urn. These are expected to be based on resources
          returned by a previous invocation of ListResources.
        }
      }, {
        :name => 'users',
        :type => :array,
        :description  => %{
          An array of user structs, which contain information about
          the users that might login to the sliver that the AM needs
          to know about. Each struct must include the key 'keys',
          which is an array of strings and can be empty. The struct
          must also include the key 'urn', which is the user's URN
          string. The users array can be empty. For example:

            [
              {
                urn: urn:publicid:IDN+geni.net:gcf+user+alice
                keys: [<ssh key>, <ssh key>]
              },
              {
                urn: urn:publicid:IDN+geni.net:gcf+user+bob
                keys: [<ssh key>]
              }
            ]
        }
      }
    ],
    :return => {
      :type => :text_xml,
      :description => %{
        The return value is an RSPEC indicating the resources that
        were allocated to the slice. The result RSPEC may contain
        additional information about the allocated resources.
      }
    }
  }

  declare :Provision, :provision, {
    :description => %{
      Request that the named geni_allocated slivers be made geni_provisioned, 
      instantiating or otherwise realizing the resources, such that they have 
      a valid geni_operational_status and may possibly be made geni_ready for 
      experimenter use. This operation is synchronous, but may start a longer process.
    },
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          The URNs of the slivers to which the resources specified in
          rspec will be allocated.
        }
      },
      {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions. Aggregates should
          ensure that the expiration time of the slice does not exceed
          the expiration time of the slice credential used to perform
          this operation.
        }
      }, {
        :name => 'rspec',
        :type => :text_xml,
        :description  => %{
          An RSPEC containing the resources that the caller is
          requesting for allocation to the slice specified in
          slice_urn. These are expected to be based on resources
          returned by a previous invocation of ListResources.
        }
      }, {
        :name => 'users',
        :type => :array,
        :description  => %{
          An array of user structs, which contain information about
          the users that might login to the sliver that the AM needs
          to know about. Each struct must include the key 'keys',
          which is an array of strings and can be empty. The struct
          must also include the key 'urn', which is the user's URN
          string. The users array can be empty. For example:

            [
              {
                urn: urn:publicid:IDN+geni.net:gcf+user+alice
                keys: [<ssh key>, <ssh key>]
              },
              {
                urn: urn:publicid:IDN+geni.net:gcf+user+bob
                keys: [<ssh key>]
              }
            ]
        }
      }
    ],
    :return => {
      :type => :text_xml,
      :description => %{
        The return value is an RSPEC indicating the resources that
        were allocated to the slice. The result RSPEC may contain
        additional information about the allocated resources.
      }
    }
  }

  declare :Renew, :renew, {
    :description => %{
      Request that the named slivers be renewed, with their expiration 
      extended. If possible, the aggregate should extend the slivers to 
      the requested expiration time, or to a sooner time if policy limits 
      apply. This method applies to slivers that are geni_allocated or to 
      slivers that are geni_provisioned, though different policies may apply 
      to slivers in the different states, resulting in much shorter max 
      expiration times for geni_allocated slivers.
    },
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          The URNs of the slivers to which will be renewed.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions.
        }
      }, {
        :name => 'expiration_time',
        :type => :string_date,
        :description  => %{
           A string in RFC 3339 format indicating the expiration_time
           desired by the caller. Note these times, per the RFC, must
           be in or relative to UTC. This time must be less than or
           equal to the slice duration in the slice credential. In
           other words, at least one supplied (slice) credential must
           still be valid at the desired new expiration time for this
           call to succeed.
        }
      }
    ],
    :return => {
      :type => :boolean,
      :description => %{
         Returns true on successful completion, false otherwise.
      }
    }
  }

  declare :Status, :status, {
    :description => "Get the status of a sliver or slivers belonging to a single slice at the given aggregate.",
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          The URNs of the slice for which the sliver status is requested.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions.
        }
      }
    ],
    :return => {
      :type => :hash,
      :description => %{
         Returns an XMLRPC struct upon successful completion. The
         struct is of the following form:
      },
      :params => [
        {
          :name => 'geni_urn',
          :type => :string_urn,
          :descriptions => %{
            The URN of the sliver as a string. This is the sliver and
            not the slice, and should be selected by the aggregate
            manager.
          }
        }, {
          :name => 'geni_status',
          :type => :string,
          :descriptions => %{
            A string indicating the status of the sliver. Possible
            values are: _configuring_, _ready_, _failed_, and
            _unknown_. Configuring indicates that at least one resource
            is being configured and none have failed. Ready indicates
            that all resources in the sliver are ready. Failed
            indicates that at least one resource in the sliver has
            failed. Unknown indicates that the state of the sliver is
            not one of the known states. More detailed information can
            be found in the value of the geni_resources member.
          }
        }, {
          :name => 'geni_resources',
          :type => :array,
          :descriptions => %{
            An array of structs. Each struct in the array gives the
            status of each resource in the sliver. The members of
            these structs are described below.

            The members of the resource struct(s) are as follows:
          },
          :params => [
            {
              :name => 'geni_urn',
              :type => :string_urn,
              :descriptions => %{
                The URN of the resource as a string. This is specific
                to the sliver, and should be selected by the aggregate
                manager to allow status reporting and control at the
                finest level supported at that aggregate. It may be a
                sliver URN if there is only 1 resource in the sliver.
              }
            }, {
              :name => 'geni_status',
              :type => :string,
              :descriptions => %{
                A string indicating the status of the
                resource. Possible values are: _configuring_, _ready_,
                _failed_, and _unknown_. *Configuring* indicates that the
                resources is being configured and is not yet ready for
                use. *Ready* indicates that the resource is
                ready. *Failed* indicates that the resource has
                failed. *Unknown* indicates that the state of the
                resource is not one of the known states.
              }
            }, {
              :name => 'geni_error',
              :type => :string,
              :descriptions => %{
                 A free form string. The aggregate manager should set
                 this to a string that could be presented to a
                 researcher to give more detailed information about
                 the state of the resource if its status is failed.
              }
            }
          ]
        }
      ]
    }
  }

  declare :PerformOperationalAction, :performOperationalAction, {
    :description => %{
      Perform the named operational action on the named slivers, possibly 
      changing the geni_operational_status of the named slivers.
    },
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          The URNs of the slivers to which will be renewed.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions.
        }
      }, {
        :name => 'action',
        :type => :string,
        :description  => %{
          The requested action.
        }
      }
    ],
    :return => {
      :type => :boolean,
      :description => %{
         Returns true on successful completion, false otherwise.
      }
    }
  }

  declare :Delete, :delete, {
    :description => %{
      Delete a sliver by stopping it if it is still running, and then
      deallocating the resources associated with it. This call will
      stop and deallocate all resources associated with the given
      slice URN.
    },
    :params => [
      {
        :name => 'urns',
        :type => :array,
        :description  => %{
          The URN of the slice whose sliver should be deleted. Or the
          URNs of the slivers that should be deleted.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in
          slice_urn. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions.
        }
      }
    ],
    :return => {
      :type => :boolean,
      :description => %{
         Returns true on success and false on failure.
      }
    }
  }

  declare :Shutdown, :shutdown_sliver, {
    :description => %{
      Perform an emergency shut down of a sliver. This operation is
      intended for administrative use. The sliver is shut down but
      remains available for further forensics.
    },
    :params => [
      {
        :name => 'slice_urn',
        :type => :string_urn,
        :description  => %{
          The URN of the slice is to have its sliver shut down.
        }
      }, {
        :name => 'credentials',
        :type => :array,
        :description  => %{
          An array of credentials. At least one credential must be a
          valid slice credential for the slice specified in slice_urn
          or a valid administrative credential with sufficient
          privileges. Note that the semantics of this argument is not
          clear. Alternative interpretations might, for example,
          accumulate privileges from each valid credential to
          determine overall caller permissions.
        }
      }
    ],
    :return => {
      :type => :boolean,
      :description => %{
         Returns true on success, false otherwise.
      }
    }
  }


end # module OMF::SFA:AM





