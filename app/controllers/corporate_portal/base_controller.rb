# frozen_string_literal: true

module CorporatePortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "corporate"

    before_action :authenticate_user!
    before_action :authenticate_corporate_user!

    helper CorporatePortal::NavigationHelper
    # Views need it to decide whether to offer "Book a stay" at all.
    helper_method :may_book_anywhere?

    private

    def corporate_relationships
      current_user.account.hotel_corporate_accounts
    end

    # The relationships this account may actually take rooms on. Booking for a
    # client is a permission each hotel grants on its own relationship, so an
    # account can be bookable at one property and billing-only at another.
    #
    # Deliberately not applied to corporate_bookings: revoking the permission
    # must not hide the stays the agent already has with the hotel.
    def bookable_relationships
      corporate_relationships.active.booking_enabled
    end

    def may_book_anywhere?
      bookable_relationships.exists?
    end

    # Only bookings this account is the billed party on. The dashboard, the
    # bookings list and the cancellation flow all scope to this, so an agent can
    # never reach another agency's reservation.
    def corporate_bookings
      Booking.where(hotel_corporate_account_id: corporate_relationships.select(:id))
    end

    def corporate_ar_invoices
      ArInvoice.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def corporate_ar_payments
      ArPayment.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def authenticate_corporate_user!
      return if current_user&.corporate? && current_user.account&.corporate?

      redirect_to root_path, alert: "You are not authorized to access the corporate portal."
    end
  end
end
