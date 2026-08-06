# frozen_string_literal: true

class AddVoidBookingsPermission < ActiveRecord::Migration[8.0]
  def up
    permission = Permission.find_or_create_by!(slug: "void_bookings") do |record|
      record.name = "Void Bookings"
    end

    Role.where(slug: %w[hotel_owner general_manager]).find_each do |role|
      RolePermission.find_or_create_by!(role:, permission:)
    end
  end

  def down
    permission = Permission.find_by(slug: "void_bookings")
    return unless permission

    RolePermission.where(permission:).delete_all
    permission.destroy!
  end
end
