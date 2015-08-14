module Petergate
  module ActionController
    module Base
      module ClassMethods
        def const_missing(const_name)
          if [:AllRest, :ALLREST].include?(const_name)
            warn "`AllRest` and `ALLREST` has been deprecated. Use :all instead."
            return ALLRESTDEP
          else
            return super 
          end
        end

        def all_actions
          ->{self.action_methods.to_a.map(&:to_sym) - [:check_access, :title]}.call
        end

        def except_actions(arr = [])
          all_actions - arr
        end

        def access(rules = {}, &block)
          if block
            b_rules = block.call
            rules = rules.merge(b_rules) if b_rules.is_a?(Hash)
          end

          instance_eval do
            @_controller_rules = rules

            def controller_rules
              @_controller_rules
            end

            def inherited(subclass)
              subclass.instance_variable_set("@_controller_rules", instance_variable_get("@_controller_rules"))
            end
          end

          class_eval do
            def check_access
              permissions(self.class.controller_rules)
            end
          end
        end
      end

      ALLRESTDEP = [:show, :index, :new, :edit, :update, :create, :destroy]

      def self.included(base)
        base.extend(ClassMethods)
        base.helper_method :logged_in?, :forbidden!
        base.before_filter do 
          unless logged_in?(:admin)
            message= defined?(check_access) ? check_access : true
            if message.is_a?(String) || message == false
              if user_signed_in?
                forbidden! message
              else
                authenticate_user!
              end
            end
          end
        end
      end

      def parse_permission_rules(rules)
        rules = rules.inject({}) do |h, (k, v)| 
          special_values = case v.class.to_s
                           when "Symbol"
                             v == :all ? self.class.all_actions : raise("No action for: #{v}")
                           when "Hash"
                             v[:except].present? ? self.class.except_actions(v[:except]) : raise("Invalid values for except: #{v.values}")
                           when "Array"
                             v
                           else
                             raise("No action for: #{v}")
                           end

          h.merge({k => special_values})
        end
        # Allows Array's of keys for he same hash.
        rules.inject({}){|h, (k, v)| k.class == Array ? h.merge(Hash[k.map{|kk| [kk, v]}]) : h.merge(k => v) }
      end

      def permissions(rules = {all: [:index, :show], customer: [], wiring: []})
        rules = parse_permission_rules(rules)
        case params[:action].to_sym
        when *(rules[:all]) # checks where the action can be seen by :all
          true
        when *(rules[:user]) # checks if the action can be seen for all users
          user_signed_in?
        when *(rules[(user_signed_in? ? current_user.role.to_sym : :all)]) # checks if action can be seen by the  current_users role. If the user isn't logged in check if it can be seen by :all
          true
        else
          false
        end
      end

      def logged_in?(*roles)
        current_user && (roles & current_user.roles).any?
      end

      def forbidden!(msg = nil)
        respond_to do |format|
          format.any(:js, :json, :xml) { render nothing: true, status: :forbidden }
          format.html do
            destination = current_user.present? ? request.referrer || after_sign_in_path_for(current_user) : root_path
            redirect_to destination, notice: msg || 'Permission Denied'
          end
        end
      end
    end
  end
end

class ActionController::Base
  include Petergate::ActionController::Base
end