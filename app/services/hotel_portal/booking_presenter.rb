# frozen_string_literal: true

module HotelPortal
  class BookingPresenter
    attr_reader :booking, :hotel

    def initialize(booking, hotel)
      @booking = booking
      @hotel = hotel
    end

    def confirmation_token
      booking.confirmation_token
    end

    def status
      booking.status
    end

    def status_label_class
      case status
      when "confirmed" then "border-green-800 text-green-800"
      when "review_no_show" then "border-amber-800 text-amber-800"
      when "checked_in" then "border-blue-800 text-blue-800"
      when "review_due_out" then "border-orange-800 text-orange-800"
      when "checkout_required" then "border-rose-800 text-rose-800"
      when "completed" then "border-emerald-800 text-emerald-800"
      when "cancelled" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def guarantee_method_display
      (booking.guarantee_method || "none").titleize
    end

    def created_at_formatted
      booking.created_at.strftime("%d %b %Y at %H:%M")
    end

    def check_in_formatted
      booking.check_in.strftime("%d %b %Y")
    end

    def check_out_formatted
      booking.check_out.strftime("%d %b %Y")
    end

    def nights_count
      (booking.check_out.to_date - booking.check_in.to_date).to_i
    end

    def nights_label
      view_context.pluralize(nights_count, "night")
    end

    def stay_summary
      "#{nights_count} #{'night'.pluralize(nights_count)} · #{booking.check_in.strftime('%d %b')}–#{booking.check_out.strftime('%d %b')}"
    end

    def guest_count_summary
      "#{booking.adults} #{'adult'.pluralize(booking.adults)} · #{booking.children.to_i} #{'child'.pluralize(booking.children.to_i)}"
    end

    def checked_in_at_form_value
      (booking.checked_in_at || Time.current).strftime("%Y-%m-%dT%H:%M")
    end

    def checked_out_at_form_value
      return booking.check_out.in_time_zone(booking.hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M") if booking.checkout_required?

      Time.current.strftime("%Y-%m-%dT%H:%M")
    end

    def check_in_title
      booking.checked_in? ? "Edit Check-In" : "Confirm Check-In"
    end

    def requires_backdated_checkin_reason?
      hotel.date_closed?(booking.check_in.to_date)
    end

    def can_manage_bookings?(user)
      user.has_permission?("manage_bookings", hotel: hotel)
    end

    def can_add_guests?(user)
      can_manage_bookings?(user) && %w[checked_in confirmed].include?(booking.status)
    end

    def additional_guests
      @additional_guests ||= booking.booking_guests.select { |booking_guest| !booking_guest.is_primary? }
    end

    def registered_guest_count
      1 + additional_guests.size
    end

    def missing_guest_record_count
      [ booking.adults.to_i + booking.children.to_i - registered_guest_count, 0 ].max
    end

    def registered_guest_count_label
      view_context.pluralize(registered_guest_count, "registered guest")
    end

    def missing_guest_record_label
      "This booking has #{view_context.pluralize(missing_guest_record_count, 'guest')} that have not been added to the guest records."
    end

    def reference_ids
      [
        [ "Confirmation", confirmation_token ],
        [ "Reservation", booking.formatted_reservation_number ],
        [ "Folio Account", booking.folio_account_reference_display ],
        [ "Guest Registration", booking.formatted_guest_registration_number ],
        [ "External", booking.external_reference ],
        [ "Channel Manager", booking.channel_manager_reference ]
      ]
    end

    def primary_guest
      @primary_guest ||= booking.primary_guest
    end

    def guest_name
      booking.guest_name
    end

    def guest_email
      booking.guest_email
    end

    def guest_phone
      booking.guest_phone
    end

    def vip?
      booking.vip?
    end

    def blacklisted?
      booking.blacklisted?
    end

    def repeat?
      booking.repeat?
    end

    def primary_guest_name
      primary_guest&.name.presence || booking.guest_name
    end

    def primary_guest_email
      primary_guest&.email.presence || booking.guest_email
    end

    def primary_guest_phone
      primary_guest&.phone.presence || booking.guest_phone
    end

    def primary_guest_country
      primary_guest&.country.presence || booking.guest_country.presence || "—"
    end

    def primary_guest_document_type
      primary_guest&.document_type.presence || booking.guest_document_type.presence || "IC/Passport"
    end

    def primary_guest_government_id
      primary_guest&.government_id.presence || booking.guest_government_id.presence || "—"
    end

    def primary_guest_email_display
      primary_guest_email.presence || "—"
    end

    def primary_guest_phone_display
      primary_guest_phone.presence || "—"
    end

    def primary_guest_document_type_display
      primary_guest_document_type.to_s.upcase
    end

    def guest_document_type_label(guest)
      guest.document_type&.upcase || "IC/Passport"
    end

    def pre_checkin_metadata
      @pre_checkin_metadata ||= (booking.pre_checkin&.metadata || {})
    end

    def estimated_arrival_time_label
      pre_checkin_metadata["estimated_arrival_time"].presence || booking.estimated_arrival_time.presence || "Not provided"
    end

    def guest_government_id_label
      pre_checkin_metadata["guest_government_id"].presence || "Not provided"
    end

    def current_room_number
      @current_room_number ||= booking.booking_rooms.first&.room_number.presence ||
                               (if booking.hotel_snapshot.is_a?(Hash)
                                  booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence
                                end)
    end

    def payment_status_display
      status = booking.payment_status.to_s
      status == "refunded" ? "cancelled" : status
    end

    def payment_status_label_class
      display_status = payment_status_display
      case display_status
      when "captured", "completed" then "border-emerald-800 text-emerald-800"
      when "pending", "authorized" then "border-yellow-800 text-yellow-800"
      when "failed", "cancelled", "refunded" then "border-red-800 text-red-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def pre_checkin_display_status
      booking.pre_checkin_display_status
    end

    def pre_checkin_status_label_class
      case pre_checkin_display_status
      when "completed" then "border-green-800 text-green-800"
      when "in_progress" then "border-blue-800 text-blue-800"
      when "failed" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def pre_checkin_badge_class
      if pre_checkin&.completed?
        "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
      else
        "bg-amber-50 text-amber-700 ring-amber-600/20"
      end
    end

    def pre_checkin_badge_label
      if pre_checkin&.completed?
        "Pre-checked"
      else
        "Pending"
      end
    end

    def room_type_prices_json
      room_types.map { |rt| [ rt.id, rt.base_price ] }.to_h.to_json
    end

    def room_type_numbers_json
      room_types.map { |rt| [ rt.id, rt.room_numbers ] }.to_h.to_json
    end

    def room_types
      @room_types ||= hotel.room_types.order(:name)
    end

    def booking_rooms
      @booking_rooms ||= booking.booking_rooms
    end

    def room_total
      booking_rooms.sum { |room| room.subtotal.to_d }
    end

    def taxes_total
      booking.tax_total.to_d
    end

    def held_security_deposit_total
      @held_security_deposit_total ||= booking.deposits.where(status: "held").sum(:amount).to_d
    end

    def projected_outstanding_balance
      (booking.booking_folio&.projected_outstanding_balance || 0).to_d
    end

    def balance_due?
      projected_outstanding_balance.positive?
    end

    def folio_forecast_count
      booking.booking_folio&.projected_forecasts&.count.to_i
    end

    def source_label
      booking.source.to_s.presence&.tr("_", " ")&.titleize || "—"
    end

    def room_summary
      summaries = booking_rooms.map do |room|
        name = room.room_type_snapshot["name"].presence || room.room_type&.name
        number = room_number_for(room)
        [ name, number.present? ? "Room #{number}" : nil ].compact.join(" · ")
      end

      summaries.reject(&:blank?).to_sentence.presence || "—"
    end

    def rate_plan_label
      booking_rooms.map { |room| room.rate_plan&.name }.compact.uniq.to_sentence.presence
    end

    def room_rate_label
      return 0.to_d unless nights_count.positive?

      (room_total / nights_count).round(2)
    end

    def room_number_for(room)
      room.room_number.presence ||
        (booking.hotel_snapshot.is_a?(Hash) ? booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence : nil)
    end

    def pre_checkin
      @pre_checkin ||= booking.pre_checkin
    end

    def housekeeping_requests
      @housekeeping_requests ||= booking.housekeeping_requests
                                        .where(archived_at: nil)
                                        .or(booking.housekeeping_requests.where(status: "cancelled"))
                                        .recent_first
    end

    def pending_housekeeping_requests_count
      @pending_housekeeping_requests_count ||= booking.housekeeping_requests.active.where(status: "pending").count
    end

    def complaint_requests
      @complaint_requests ||= booking.complaint_requests
                                     .where(archived_at: nil)
                                     .or(booking.complaint_requests.where(status: "cancelled"))
                                     .recent_first
    end

    def pending_complaint_requests_count
      @pending_complaint_requests_count ||= booking.complaint_requests.active.where(status: "pending").count
    end

    def pending_requests_count
      pending_housekeeping_requests_count + pending_complaint_requests_count
    end

    def suggested_late_checkout_amount
      primary_room = booking.booking_rooms.first
      return 0.to_d unless primary_room&.room_type

      room_type = primary_room.room_type
      quantity = primary_room.quantity.to_i

      today = Time.current.to_date
      rate = room_type.room_rates.find_by(date: today)&.price || room_type.base_price

      base_amount = (rate.to_d * quantity).round(2)

      applicable_taxes = hotel.hotel_taxes.enabled.to_a
      taxes_amount = applicable_taxes.sum { |tax| tax.compute(rooms_subtotal: base_amount) }

      nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
      per_night_tourism_tax = nights.positive? ? (booking.tourism_tax_amount.to_d / nights).round(2) : 0.to_d

      (base_amount + taxes_amount + per_night_tourism_tax).round(2)
    end

    def currency
      booking.currency.presence || "MYR"
    end

    def notes_json
      booking.booking_notes.includes(:user).map { |n|
        {
          body: n.body,
          author: n.user.name,
          date: n.created_at.strftime("%b %d, %Y %H:%M")
        }
      }.to_json
    end

    def guarantee_method_options
      Booking::GUARANTEE_METHODS.map { |m| [ m.titleize, m ] }
    end

    def can_request_refund?
      (booking.status == "cancelled" || booking.status == "confirmed") && booking.refund_request.blank?
    end

    def refund_eligibility
      @refund_eligibility ||= Refunds::Eligibility.new(booking).call
    end

    def occupancy_text(variant: :desktop)
      if variant == :desktop
        "#{booking.adults} #{'adult'.pluralize(booking.adults)} · #{booking.children.to_i} ch."
      else
        "#{booking.adults}A · #{booking.children.to_i}C"
      end
    end

    def room_display_text(variant: :desktop)
      primary_room = booking.booking_rooms.first
      return "—" unless primary_room

      room_no = room_number_for(primary_room)
      room_type = primary_room.room_type_snapshot["name"].presence || primary_room.room_type&.name

      if variant == :desktop
        room_no.present? ? "Room #{room_no} · #{room_type}" : room_type
      else
        room_no.present? ? "#{room_type} · #{room_no}" : room_type
      end
    end

    def formatted_projected_balance
      format_currency(projected_outstanding_balance)
    end

    def payment_status_label
      payment_status_display.to_s.tr("_", " ").titleize.presence || "—"
    end

    def guarantee_method_label
      booking.guarantee_method.to_s.presence&.tr("_", " ")&.titleize || "No guarantee"
    end

    def security_deposit_status_label
      booking.deposit_status.to_s.presence&.tr("_", " ")&.titleize || "Not Required"
    end

    def formatted_room_total
      format_currency(room_total)
    end

    def formatted_taxes_total
      format_currency(taxes_total)
    end

    def formatted_held_security_deposit_total
      format_currency(held_security_deposit_total)
    end

    def formatted_total_amount
      format_currency(booking.total_amount)
    end

    def guest_name_initial
      booking.guest_name&.chr || "G"
    end

    def primary_room_type_name
      booking.booking_rooms.first&.room_type&.name || "Room"
    end

    def formatted_check_in_date
      booking.check_in.strftime("%b %d")
    end

    def formatted_check_out_date
      booking.check_out.strftime("%b %d")
    end

    def dashboard_status_badge_class
      case status
      when "confirmed" then "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
      when "cancelled" then "bg-red-50 text-red-700 ring-red-600/20"
      else "bg-slate-100 text-slate-700 ring-slate-500/20"
      end
    end

    def dashboard_status_label
      status.titleize
    end

    def formatted_total_amount_dashboard
      "RM #{view_context.number_with_precision(booking.total_amount, precision: 2)}"
    end

    def self.status_pill_style(status)
      booking_pill_styles = {
        "pending" => "peer-checked:border-amber-400 peer-checked:bg-amber-50 peer-checked:text-amber-700 peer-checked:hover:bg-amber-100",
        "confirmed" => "peer-checked:border-blue-400 peer-checked:bg-blue-50 peer-checked:text-blue-700 peer-checked:hover:bg-blue-100",
        "review_no_show" => "peer-checked:border-amber-500 peer-checked:bg-amber-50 peer-checked:text-amber-800 peer-checked:hover:bg-amber-100",
        "checked_in" => "peer-checked:border-violet-400 peer-checked:bg-violet-50 peer-checked:text-violet-700 peer-checked:hover:bg-violet-100",
        "review_due_out" => "peer-checked:border-orange-400 peer-checked:bg-orange-50 peer-checked:text-orange-700 peer-checked:hover:bg-orange-100",
        "checkout_required" => "peer-checked:border-rose-400 peer-checked:bg-rose-50 peer-checked:text-rose-700 peer-checked:hover:bg-rose-100",
        "completed" => "peer-checked:border-emerald-400 peer-checked:bg-emerald-50 peer-checked:text-emerald-700 peer-checked:hover:bg-emerald-100",
        "cancelled" => "peer-checked:border-slate-500 peer-checked:bg-slate-100 peer-checked:text-slate-700 peer-checked:hover:bg-slate-200",
        "no_show" => "peer-checked:border-rose-400 peer-checked:bg-rose-50 peer-checked:text-rose-700 peer-checked:hover:bg-rose-100",
        "overbooked" => "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700 peer-checked:hover:bg-red-100",
        "not_ready" => "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700 peer-checked:hover:bg-red-100"
      }
      booking_pill_styles[status] || "peer-checked:bg-slate-900 peer-checked:text-white peer-checked:border-slate-900"
    end

    def created_at_date
      booking.created_at.strftime("%d %b %Y")
    end

    def status_variant_class
      booking_styles = {
        "pending" => "border-amber-200 bg-amber-50 text-amber-700",
        "confirmed" => "border-blue-200 bg-blue-50 text-blue-700",
        "review_no_show" => "border-amber-300 bg-amber-50 text-amber-800",
        "checked_in" => "border-violet-200 bg-violet-50 text-violet-700",
        "review_due_out" => "border-orange-200 bg-orange-50 text-orange-700",
        "checkout_required" => "border-rose-200 bg-rose-50 text-rose-700",
        "completed" => "border-emerald-200 bg-emerald-50 text-emerald-700",
        "cancelled" => "border-slate-300 bg-slate-100 text-slate-600",
        "no_show" => "border-rose-200 bg-rose-50 text-rose-700",
        "overbooked" => "border-red-200 bg-red-50 text-red-700",
        "not_ready" => "border-red-200 bg-red-50 text-red-700"
      }
      booking_styles[status] || "border-slate-200 bg-slate-50 text-slate-600"
    end

    def status_label_humanized
      status.humanize
    end

    def check_in_short
      booking.check_in.strftime("%d %b")
    end

    def check_out_date_year
      booking.check_out.strftime("%d %b %Y")
    end

    def formatted_currency_total
      "#{currency} #{view_context.number_with_precision(booking.total_amount, precision: 2)}"
    end

    def guest_email_display
      booking.guest_email.presence || "—"
    end

    def guest_phone_display
      booking.guest_phone.presence || "—"
    end

    private

    def format_currency(amount)
      "#{currency} #{view_context.number_with_precision(amount, precision: 2)}"
    end

    def view_context
      ActionController::Base.helpers
    end
  end
end
