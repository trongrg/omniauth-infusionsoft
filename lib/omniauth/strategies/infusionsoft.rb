require 'omniauth/strategies/oauth2'
require 'omniauth/infusionsoft/signed_request'
require 'openssl'
require 'rack/utils'
require 'uri'

module OmniAuth
  module Strategies
    class Infusionsoft < OmniAuth::Strategies::OAuth2
      class NoAuthorizationCodeError < StandardError; end

      DEFAULT_SCOPE = 'full'

      option :client_options, {
        :site => 'https://signin.infusionsoft.com',
        :authorize_url => "https://signin.infusionsoft.com/app/oauth/authorize",
        :token_url => 'https://api.infusionsoft.com/token'
      }

      option :token_params, {
        :parse => :json
      }

      option :access_token_options, {
        :header_format => 'OAuth %s',
        :param_name => 'access_token'
      }

      option :authorize_options, [:scope, :display, :auth_type]

      uid {
        access_token.params['scope']
      }

      info do
        access_token.params
      end

      extra do
        hash = {}
        prune! hash
      end

      def callback_phase
        with_authorization_code! do
          super
        end
      rescue NoAuthorizationCodeError => e
        fail!(:no_authorization_code, e)
      rescue OmniAuth::Infusionsoft::SignedRequest::UnknownSignatureAlgorithmError => e
        fail!(:unknown_signature_algorithm, e)
      end

      # NOTE If we're using code from the signed request then FB sets the redirect_uri to '' during the authorize
      #      phase and it must match during the access_token phase:
      #      https://github.com/infusionsoft/infusionsoft-php-sdk/blob/master/src/base_infusionsoft.php#L477
      def callback_url
        if @authorization_code_from_signed_request_in_cookie
          ''
        else
          options[:callback_url] || super
        end
      end

      def access_token_options
        options.access_token_options.inject({}) { |h,(k,v)| h[k.to_sym] = v; h }
      end

      # You can pass +display+, +scope+, or +auth_type+ params to the auth request, if you need to set them dynamically.
      # You can also set these options in the OmniAuth config :authorize_params option.
      #
      # For example: /auth/infusionsoft?display=popup
      def authorize_params
        super.tap do |params|
          %w[display scope auth_type].each do |v|
            if request.params[v]
              params[v.to_sym] = request.params[v]
            end
          end

          params[:scope] ||= DEFAULT_SCOPE
        end
      end

      protected

      def build_access_token
        super.tap do |token|
          token.options.merge!(access_token_options)
        end
      end

      private

      def signed_request_from_cookie
        @signed_request_from_cookie ||= raw_signed_request_from_cookie && OmniAuth::Infusionsoft::SignedRequest.parse(raw_signed_request_from_cookie, client.secret)
      end

      def raw_signed_request_from_cookie
        request.cookies["fbsr_#{client.id}"]
      end

      # Picks the authorization code in order, from:
      #
      # 1. The request 'code' param (manual callback from standard server-side flow)
      # 2. A signed request from cookie (passed from the client during the client-side flow)
      def with_authorization_code!
        if request.params.key?('code')
          yield
        elsif code_from_signed_request = signed_request_from_cookie && signed_request_from_cookie['code']
          request.params['code'] = code_from_signed_request
          @authorization_code_from_signed_request_in_cookie = true
          # NOTE The code from the signed fbsr_XXX cookie is set by the FB JS SDK will confirm that the identity of the
          #      user contained in the signed request matches the user loading the app.
          original_provider_ignores_state = options.provider_ignores_state
          options.provider_ignores_state = true
          begin
            yield
          ensure
            request.params.delete('code')
            @authorization_code_from_signed_request_in_cookie = false
            options.provider_ignores_state = original_provider_ignores_state
          end
        else
          raise NoAuthorizationCodeError, 'must pass either a `code` (via URL or by an `fbsr_XXX` signed request cookie)'
        end
      end

      def prune!(hash)
        hash.delete_if do |_, value|
          prune!(value) if value.is_a?(Hash)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end
    end
  end
end
