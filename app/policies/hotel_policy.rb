class HotelPolicy < ApplicationPolicy
  def index?
    user.superadmin? || user.hotels.any?
  end

  def show?
    user.superadmin? || user.hotels.include?(record)
  end

  def update?
    user.superadmin? || user.user_hotel_accesses.find_by(hotel: record)&.role&.permissions&.exists?(slug: "manage_hotel_profile")
  end

  class Scope < Scope
    def resolve
      if user.superadmin?
        scope.all
      else
        user.hotels
      end
    end
  end
end
