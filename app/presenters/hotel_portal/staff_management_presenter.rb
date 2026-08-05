# frozen_string_literal: true

module HotelPortal
  # View model for Settings › Team › Staff Management.
  #
  # Both tables on that page are read-only listings — role and access status are
  # edited in a sheet — so every cell, badge tone, and action path is resolved
  # here and the templates stay declarative.
  class StaffManagementPresenter
    StaffRow = Data.define(
      :id,
      :name,
      :email,
      :role_name,
      :active,
      :status_label,
      :status_toggleable,
      :status_locked_reason,
      :own_row,
      :deletable,
      :status_path,
      :edit_path,
      :delete_path
    )

    InvitationRow = Data.define(
      :id,
      :email,
      :role_name,
      :invited_by,
      :expires_at,
      :edit_path,
      :resend_path,
      :revoke_path
    )

    attr_reader :hotel, :current_user

    def initialize(hotel:, current_user:)
      @hotel = hotel
      @current_user = current_user
    end

    def staff_rows
      @staff_rows ||= accesses.map { |access| staff_row(access) }
    end

    def invitation_rows
      @invitation_rows ||= invitations.map { |invitation| invitation_row(invitation) }
    end

    def staff? = staff_rows.any?
    def invitations? = invitation_rows.any?

    # Permanent deletion is unrecoverable, so it is gated on account management
    # rather than the manage_users permission that merely opens this page.
    def may_delete?
      return @may_delete if defined?(@may_delete)

      @may_delete = current_user.has_permission?(
        UserHotelAccess::ACCOUNT_MANAGEMENT_PERMISSION,
        hotel: hotel
      )
    end

    private

    def accesses
      hotel.user_hotel_accesses
           .includes(:user, role: :permissions)
           .in_directory_order
    end

    def invitations
      hotel.staff_invitations.pending.includes(:role, :invited_by_user).order(created_at: :desc)
    end

    def staff_row(access)
      own_row = access.user_id == current_user.id
      sole_manager = access.sole_account_manager?

      StaffRow.new(
        id: access.id,
        name: access.user.name,
        email: access.user.email,
        role_name: access.role.name,
        active: access.active?,
        status_label: access.active? ? "Active" : "Revoked",
        status_toggleable: !own_row && !sole_manager,
        status_locked_reason: status_locked_reason(own_row, sole_manager),
        own_row: own_row,
        deletable: may_delete? && !own_row && !sole_manager,
        status_path: routes.status_hotel_user_path(hotel, access),
        edit_path: routes.edit_hotel_user_path(hotel, access),
        delete_path: routes.hotel_user_path(hotel, access)
      )
    end

    # Spelled out rather than left to a disabled control, so the switch never
    # reads as merely broken.
    def status_locked_reason(own_row, sole_manager)
      return "You cannot revoke your own access." if own_row
      return "The only account manager cannot be revoked." if sole_manager

      nil
    end

    def invitation_row(invitation)
      InvitationRow.new(
        id: invitation.id,
        email: invitation.email,
        role_name: invitation.role&.name,
        invited_by: invitation.invited_by_user.name,
        expires_at: invitation.expires_at,
        edit_path: routes.edit_hotel_staff_invitation_path(hotel, invitation),
        resend_path: routes.resend_hotel_staff_invitation_path(hotel, invitation),
        revoke_path: routes.hotel_staff_invitation_path(hotel, invitation)
      )
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
