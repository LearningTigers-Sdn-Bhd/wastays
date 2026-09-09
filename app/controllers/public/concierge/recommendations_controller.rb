# frozen_string_literal: true

module Public
  module Concierge
    # Local partner vendors and the vouchers a guest can claim from them.
    #
    # Browsing is open: the vendor list is a curated local directory and there
    # is nothing to abuse in reading it. Claiming is gated on a confirmation
    # code for a live stay, which is the point at which something of value
    # changes hands. A second factor at first claim is the intended next layer;
    # `require_booking!` is the single place it will go.
    class RecommendationsController < BaseController
      rescue_from VendorDirectory::VendorNotFound, VendorDirectory::OfferNotFound, with: :vendor_not_found

      before_action :load_categories
      before_action :load_category, only: :index
      before_action :load_vendor, only: [ :vendor, :offer, :claim ]
      before_action :load_offer, only: [ :offer, :claim ]
      before_action :require_booking!, only: [ :wallet, :claim ]
      before_action :load_return_to, only: [ :new, :lookup ]

      def index
        @vendors = VendorDirectory.vendors_in(@category.slug)
        @featured = VendorDirectory.featured_in(@category.slug)
        @all_offers = VendorDirectory.offers_in(@category.slug)
      end

      def vendor
      end

      def offer
        @entry = voucher_wallet&.find(@offer)
      end

      def claim
        @entry = voucher_wallet.claim!(@offer)
        redirect_to concierge_recommendation_offer_path(@hotel, @vendor, @offer),
                    notice: "Voucher claimed. Show the QR code at #{@vendor.name}."
      end

      def wallet
        @entries = voucher_wallet.entries
      end

      # The gate. Reached only when a guest asks to claim without a live booking
      # in the session.
      def new
      end

      def lookup
        booking = resolve_concierge_booking_from_params(
          missing_token_message: "Please enter your booking confirmation code.",
          not_found_message: "We could not find that booking. Check the code on your confirmation email."
        )
        return unless booking

        unless stay_live?(booking)
          @error = "Vouchers are for guests currently staying with us. Please see the front desk."
          clear_concierge_booking_cookie
          return render :new, status: :unprocessable_content
        end

        redirect_to @return_to
      end

      private

      def load_return_to = @return_to = safe_return_to

      def load_categories
        @categories = VendorDirectory.visible_categories
      end

      def load_category
        slug = params[:category].presence || @categories.first&.slug
        @category = VendorDirectory.category(slug) or return vendor_not_found
      end

      def load_vendor = @vendor = VendorDirectory.vendor(params[:vendor_id])

      def load_offer = @offer = VendorDirectory.offer(@vendor.id, params[:offer_id])

      # Nil until a stay is confirmed, which is exactly what the views want to
      # branch on: no booking means nothing has been claimed and nothing can be.
      def voucher_wallet
        return if current_concierge_booking.blank?

        @voucher_wallet ||= ::Concierge::VoucherWallet.new(
          session: session,
          booking: current_concierge_booking
        )
      end
      helper_method :voucher_wallet

      def require_booking!
        return if current_concierge_booking.present?

        redirect_to concierge_recommendations_unlock_path(@hotel, return_to: request.fullpath)
      end

      # A voucher is a benefit of the stay, so the stay has to be happening.
      def stay_live?(booking)
        return true if booking.status == "checked_in"

        booking.status == "confirmed" && booking.check_in.to_date <= Time.zone.today &&
          booking.check_out.to_date >= Time.zone.today
      end

      # Only ever bounce back inside this section, so the gate cannot be turned
      # into an open redirect.
      def safe_return_to
        candidate = params[:return_to].to_s
        prefix = concierge_recommendations_path(@hotel)
        return candidate if candidate.start_with?("#{prefix}/") || candidate.split("?").first == prefix

        prefix
      end

      def vendor_not_found
        redirect_to concierge_recommendations_path(@hotel),
                    alert: "That listing is no longer available."
      end
    end
  end
end
