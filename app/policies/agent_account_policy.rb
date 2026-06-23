class AgentAccountPolicy < ApplicationPolicy
  def index?
    user.superadmin? || user.has_permission?(:view_agent_accounts)
  end

  def show?
    user.superadmin? || user.has_permission?(:view_agent_accounts)
  end

  def create?
    user.superadmin? || user.has_permission?(:manage_agent_accounts)
  end

  def update?
    user.superadmin? || user.has_permission?(:manage_agent_accounts)
  end

  def destroy?
    user.superadmin? || user.has_permission?(:manage_agent_accounts)
  end

  class Scope < Scope
    def resolve
      if user.superadmin?
        scope.all
      else
        scope.where(hotel_id: user.hotel_ids)
      end
    end
  end
end
