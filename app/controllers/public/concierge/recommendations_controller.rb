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
      before_action :load_vendor, only: [ :vendor, :offer, :claim, :create_review ]
      before_action :load_offer, only: [ :offer, :claim ]
      before_action :require_booking!, only: [ :wallet, :claim ]
      before_action :load_return_to, only: [ :new, :lookup ]

      def index
        @vendors = VendorDirectory.vendors_in(@category.slug)
        @featured = VendorDirectory.featured_in(@category.slug)
        @all_offers = VendorDirectory.offers_in(@category.slug)
      end

      def vendor
        @reviews = review_book.for(@vendor)
        @review_form = ::Concierge::VendorReviewForm.new
      end

      # Reviewing is open to any guest reading the page, not gated on a live
      # stay the way claiming a voucher is -- there is nothing of value
      # changing hands here, just an opinion.
      def create_review
        @review_form = ::Concierge::VendorReviewForm.new(review_form_params)

        if @review_form.valid?
          review_book.add!(vendor_id: @vendor.id, guest_name: @review_form.guest_name,
                            rating: @review_form.rating, comment: @review_form.comment)
          redirect_to concierge_recommendation_vendor_path(@hotel, @vendor, anchor: "reviews"),
                      notice: "Thanks for the review!"
        else
          @reviews = review_book.for(@vendor)
          render :vendor, status: :unprocessable_content
        end
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
        @dev_sample_booking = dev_sample_booking
        @dev_sample_code = @dev_sample_booking&.booking_confirmation_token&.token
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

        redirect_to resolved_return_target
      end

      private

      def load_return_to = @return_to = safe_return_to

      # request.fullpath on the claim action -- what require_booking! sends
      # here as return_to -- names a POST-only route. redirect_to always sends
      # the browser back with a GET, and there is no GET route at that path,
      # so bouncing straight there 404s. Recognise that specific case, finish
      # the claim now that a booking is on hand, and land on the offer page
      # instead -- the same page the claim action itself redirects to, so nothing
      # about the outcome changes, only how the guest arrives at it. Anything
      # else return_to might name (the index, a vendor page) is a normal GET
      # and passes through untouched.
      def resolved_return_target
        match = recognized_claim_route(@return_to)
        return @return_to unless match

        vendor = VendorDirectory.vendor(match[:vendor_id])
        offer = VendorDirectory.offer(vendor.id, match[:offer_id])
        voucher_wallet.claim!(offer)
        concierge_recommendation_offer_path(@hotel, vendor, offer)
      rescue VendorDirectory::VendorNotFound, VendorDirectory::OfferNotFound
        @return_to
      end

      def recognized_claim_route(path)
        match = Rails.application.routes.recognize_path(path, method: :post)
        return unless match[:controller] == "public/concierge/recommendations" && match[:action] == "claim"

        match
      rescue ActionController::RoutingError
        nil
      end

      # A one-click way to reach the claim + QR screens locally without a real
      # confirmation code in hand. Never rendered outside development -- the
      # view guards on this being present, and this only looks a booking up
      # when Rails.env.local? is true, so there is nothing to gate twice.
      #
      # The code a guest types is booking_confirmation_token#token, not
      # bookings.confirmation_token -- Booking::with_confirmation_token joins
      # on the former, deliberately a separate, opaque value from the
      # human-readable reference printed on the booking itself. Only a
      # booking with that association loaded is worth offering here.
      def dev_sample_booking
        return unless Rails.env.local?

        candidates = @hotel.bookings.where(status: "checked_in")
                            .or(@hotel.bookings.where(status: "confirmed")
                                       .where("check_in <= ? AND check_out >= ?", Time.zone.today, Time.zone.today))
                            .includes(:booking_confirmation_token)

        candidates.find { |booking| booking.booking_confirmation_token.present? }
      end

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

      def review_book = @review_book ||= ::Concierge::ReviewBook.new(session: session)

      def review_form_params
        params.fetch(:concierge_vendor_review_form, {}).permit(:guest_name, :rating, :comment)
      end

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
