
require 'omf_common/lobject'
require 'omf-sfa/am/am-rest/am_authorizer'
require 'omf-sfa/am/am-rest/sam_authorizer'
require 'rack'


module OMF::SFA::AM::Rest
  class SamantSessionAuthenticator < SessionAuthenticator


    def initialize(app, opts = {})
      @app = app
      @opts = opts
      @opts[:no_session] = (@opts[:no_session] || []).map { |s| Regexp.new(s) }
      if @opts[:expire_after]
        @@expire_after = @opts[:expire_after]
      end
      @@active = true
    end


    def call(env)
      req = ::Rack::Request.new(env)
      method = req.request_method # epikoinwnei me to rack interface kai vlepei poia methodos exei zhththei (px GET)
      path_info = req.path_info

      if method == 'GET'
        debug "Rest Request: " + req.inspect
        debug "GET REST REQUEST"

        body = req.body
        unless body.nil?
          debug "body = " + body.gets
        end
        raise EmptyBodyException.new if body.nil?
        (body = body.string) if body.is_a? StringIO
        if body.is_a? Tempfile
          tmp = body
          body = body.read
          tmp.rewind
        end
        raise EmptyBodyException.new if body.empty?

        content_type = req.content_type
        raise UnsupportedBodyFormatException.new unless content_type == 'application/json'

        jb = JSON.parse(body)
        debug "json body = " + jb.inspect
        account = nil
        if jb.kind_of? Hash
          account = jb['credentials']['account'].nil? ? nil : jb['credentials']['account']['name']
        end

        debug "account name  = " + account.inspect
        # raise UnsupportedBodyFormatException.new
        # req.session[:authorizer] = AMAuthorizer.create_for_rest_request(env['rack.authenticated'], env['rack.peer_cert'], req.params["account"], @opts[:am_manager])
        req.session[:authorizer] = SAMAuthorizer.create_for_rest_request(env['rack.authenticated'], env['rack.peer_cert'], account, @opts[:am_manager], jb['credentials'])
      elsif method == 'OPTIONS'
        #do nothing for OPTIONS  
      elsif env["REQUEST_PATH"] == '/mapper'
        req.session[:authorizer] = SAMAuthorizer.create_for_rest_request(env['rack.authenticated'], env['rack.peer_cert'], req.params["account"], @opts[:am_manager])
      else
        debug "MISC REST REQUEST"
        body = req.body
        debug "body = " + body.gets
        raise EmptyBodyException.new if body.nil?
        (body = body.string) if body.is_a? StringIO
        if body.is_a? Tempfile
          tmp = body
          body = body.read
          tmp.rewind
        end
        raise EmptyBodyException.new if body.empty?

        content_type = req.content_type
        raise UnsupportedBodyFormatException.new unless content_type == 'application/json'

        jb = JSON.parse(body)
        account = nil
        if jb.kind_of? Hash
          account = jb['credentials']['account'].nil? ? nil : jb['credentials']['account']['name']
        end
        
        req.session[:authorizer] = SAMAuthorizer.create_for_rest_request(env['rack.authenticated'], env['rack.peer_cert'], account, @opts[:am_manager], jb['credentials'])
      end

      status, headers, body = @app.call(env)
      # if sid
      #   headers['Set-Cookie'] = "sid=#{sid}"  ##: name2=value2; Expires=Wed, 09-Jun-2021 ]
      # end
      [status, headers, body]
    rescue OMF::SFA::AM::InsufficientPrivilegesException => ex
      body = {
        :error => {
          :reason => ex.to_s,
        }
      }
      warn "ERROR: #{ex}"
      # debug ex.backtrace.join("\n")
      
      return [401, { "Content-Type" => 'application/json', 'Access-Control-Allow-Origin' => '*', 'Access-Control-Allow-Methods' => 'GET, PUT, POST, OPTIONS' }, JSON.pretty_generate(body)]
    rescue EmptyBodyException => ex
      body = {
        :error => {
          :reason => ex.to_s,
        }
      }
      warn "ERROR: #{ex}"
      # debug ex.backtrace.join("\n")
      
      return [400, { "Content-Type" => 'application/json', 'Access-Control-Allow-Origin' => '*', 'Access-Control-Allow-Methods' => 'GET, PUT, POST, OPTIONS' }, JSON.pretty_generate(body)]
    rescue UnsupportedBodyFormatException => ex
      body = {
        :error => {
          :reason => ex.to_s,
        }
      }
      warn "ERROR: #{ex}"
      # debug ex.backtrace.join("\n")
      
      return [400, { "Content-Type" => 'application/json', 'Access-Control-Allow-Origin' => '*', 'Access-Control-Allow-Methods' => 'GET, PUT, POST, OPTIONS' }, JSON.pretty_generate(body)]
    end


  end # class

end # module




