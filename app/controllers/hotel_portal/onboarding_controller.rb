# frozen_string_literal: true

module HotelPortal
  class OnboardingController < BaseController
    layout "onboarding"

    # Sections that have their own form and completion contract. Everything else
    # still runs on the shell's placeholder contract, which Onboarding::Readiness
    # treats as a blocking issue so a stub cannot be submitted. The view reads the
    # same list, so the two cannot drift.
    IMPLEMENTED_SECTIONS = %w[
      property_profile
      property_photos
      roles_permissions
      staff_setup
      taxes_fees
      room_revenue
      rooms
      rates_availability
      extra_charges
      discounts
      payment_methods
      corporate_accounts
      channel_manager
      review
    ].freeze

    # No implemented section takes a skip action. Each optional one answers
    # itself: an empty table states the decision, and the section's own save
    # service records it — see Onboarding::SkipOptionalSection for the decisions
    # they write. A separate skip control would only ask the same thing twice.
    before_action :authorize_onboarding!
    before_action :redirect_completed_onboarding
    before_action :build_navigation
    before_action :set_current_entry, except: :index
    before_action :redirect_locked_section, only: :show

    def index
      redirect_to onboarding_path(@navigation.resume_entry)
    end

    def show
      prepare_section
    end

    def update
      return redirect_read_only if pending_review?

      if implemented_section?
        update_implemented_section
      else
        update_placeholder_section
      end
    end

    private

    def authorize_onboarding!
      authorize current_hotel, :update?, policy_class: HotelPolicy
    end

    # Onboarding is over once the property is live. Everyone goes to the dashboard —
    # the property is open and this is no longer where the work happens. The submitted
    # setup is still readable in full on the admin onboarding page, which holds the
    # immutable snapshot.
    def redirect_completed_onboarding
      return unless current_hotel.status == "live"

      redirect_to hotel_dashboard_path(current_hotel)
    end

    def build_navigation
      @navigation = Onboarding::NavigationState.new(hotel: current_hotel).call
    end

    def set_current_entry
      @current_entry = @navigation.fetch(params[:section_key])
    rescue KeyError
      raise ActiveRecord::RecordNotFound
    end

    def redirect_locked_section
      return if pending_review? && @current_entry.definition.key == "review"
      return if @current_entry.available

      redirect_to onboarding_path(@navigation.resume_entry),
                  alert: "Complete the earlier onboarding steps before opening this page."
    end

    def prepare_section(entries: nil)
      @presenter = OnboardingPresenter.new(
        hotel: current_hotel,
        navigation: @navigation,
        current_entry: @current_entry
      )

      case @current_entry.definition.key
      # The profile step reads star ratings off the presenter; the photos step
      # also reads the upload queue from it.
      when "property_profile", "property_photos"
        @photo_queue = HotelPortal::PhotoQueue.new(current_hotel, session)
        @profile_presenter = HotelPortal::ProfilePresenter.new(current_hotel, @photo_queue, view_context)
      when "roles_permissions"
        @preset_roles = preset_roles.includes(:permissions)
      when "staff_setup"
        @staff_roles = preset_roles
        @staff_entries = entries || current_hotel.onboarding_staff_drafts.includes(:role).order(:created_at, :id).map do |draft|
          {
            "name" => draft.name,
            "email" => draft.email,
            "role_id" => draft.role_id.to_s,
            "role_slug" => draft.role.slug,
            "role_name" => draft.role.name,
            "send_invitation" => draft.send_invitation.to_s
          }
        end
        # No trailing blank row: an empty table is a valid answer here, and a row
        # already waiting to be filled in argues with the empty state saying so.
        # Rows are added deliberately instead.
      when "taxes_fees"
        # No trailing blank row here: its required fields would block submission
        # for a property that simply has no fees of its own. Rows are added
        # deliberately instead.
        @tax_entries = entries || persisted_tax_entries
      when "room_revenue"
        @room_revenue_presenter = HotelPortal::RoomRevenuePresenter.new(hotel: current_hotel, active_tab: "tax_rules")
      when "rooms"
        @room_entries = entries || persisted_room_entries
        @room_entries = [ {} ] if @room_entries.empty? && !@presenter.read_only?
        @room_amenity_choices = Hotel::CATEGORIZED_ROOM_AMENITIES.flat_map do |group|
          group[:items].map { |amenity| { label: "#{group[:category]} · #{amenity[:name]}", value: amenity[:id].to_s } }
        end
      when "rates_availability"
        prepare_rates_availability(entries: entries)
      when "extra_charges"
        # A review reads the saved charges; only the editor works from entries,
        # which may be a failed submission rather than what is stored.
        if @presenter.read_only?
          @extra_charges = current_hotel.hotel_extra_charges.includes(:transaction_code).ordered
        else
          @extra_charge_entries = entries || persisted_extra_charge_entries
          @tax_rule_choices = TaxRuleOptionsQuery.new(current_hotel).choices
          # Percentage pricing is a property of the record, not of the
          # submission: the table has no field for it, so a failed save that
          # hands back what was typed still has to know which rows are one.
          @percentage_extra_charges = current_hotel.hotel_extra_charges.where(pricing_type: "percentage")
                                                   .includes(:transaction_code).index_by { |charge| charge.id.to_s }
        end
      when "discounts"
        # A review reads the saved discounts; only the editor works from entries,
        # which may be a failed submission rather than what is stored.
        if @presenter.read_only?
          @discounts = current_hotel.hotel_discounts.includes(:transaction_code).ordered
        else
          @discount_entries = entries || persisted_discount_entries
          @charge_code_choices = discount_charge_code_choices
          @extra_charges_skipped = @navigation.fetch("extra_charges").record.state == "skipped"
        end
      when "payment_methods"
        # A review reads the saved methods; only the editor works from entries,
        # which may be a failed submission rather than what is stored.
        if @presenter.read_only?
          @payment_methods = current_hotel.hotel_payment_methods.includes(:transaction_code).ordered
        else
          @payment_method_entries = entries || persisted_payment_method_entries
        end
      when "corporate_accounts"
        # See staff_setup: no trailing blank row, because empty is an answer.
        @corporate_draft_entries = entries || persisted_corporate_draft_entries
      when "channel_manager"
        # See staff_setup: no trailing blank row, because empty is an answer.
        @ota_credential_entries = entries || persisted_ota_credential_entries
      when "review"
        rates_coverage = Rates::SetupCoverage.call(hotel: current_hotel)
        @readiness = Onboarding::Readiness.new(hotel: current_hotel, rates_coverage:).call
        @submission = current_hotel.onboarding_submissions
                                   .includes(:submitted_by, :reviewed_by, :deliveries)
                                   .newest_first.first
        snapshot = if @presenter.read_only? && @submission.present?
          @submission.snapshot
        else
          Onboarding::SubmissionSnapshot.call(hotel: current_hotel, rates_coverage:).data
        end
        @review_presenter = OnboardingReviewPresenter.new(
          hotel: current_hotel, navigation: @navigation, readiness: @readiness,
          submission: @submission, snapshot:
        )
        @submission_idempotency_key = SecureRandom.uuid unless @presenter.read_only?
      end
    end

    # The stored password is never among these. It is write-only from the hotel
    # portal: the owner replaces it or leaves it alone, and only the WAStays team
    # ever reads it back.
    def persisted_ota_credential_entries
      current_hotel.hotel_ota_credentials.ordered.map do |record|
        {
          "id" => record.id.to_s,
          "client_key" => "ota-credential-#{record.id}",
          "channel_name" => record.channel_name,
          "property_code" => record.property_code,
          "username" => record.username,
          "password_saved" => record.password_saved?.to_s,
          "market_manager_name" => record.market_manager_name,
          "market_manager_phone" => record.market_manager_phone,
          "market_manager_email" => record.market_manager_email
        }
      end
    end

    def persisted_corporate_draft_entries
      current_hotel.onboarding_corporate_drafts.order(:created_at, :id).map do |draft|
        {
          "id" => draft.id.to_s,
          "client_key" => "corporate-draft-#{draft.id}",
          "email" => draft.email,
          "company_name" => draft.company_name,
          "account_type" => draft.account_type,
          "relationship_type" => draft.relationship_type,
          "credit_limit" => draft.credit_limit&.to_s,
          "credit_currency" => draft.credit_currency,
          "payment_terms_days" => draft.payment_terms_days&.to_s,
          "send_invitation" => draft.send_invitation.to_s,
          "delivered" => draft.delivered?.to_s
        }
      end
    end

    def persisted_payment_method_entries
      adopted = current_hotel.hotel_payment_methods.includes(:transaction_code).ordered.map do |method|
        {
          "id" => method.id.to_s,
          "client_key" => "payment-method-#{method.id}",
          # The standard codes every property is given are shown, not edited.
          # A hint for the table only: the save path decides this again from the
          # record rather than trusting what comes back.
          "locked" => method.transaction_code.system_required?.to_s,
          "name" => method.name,
          "code" => method.code,
          "payment_method_type" => method.payment_method_type,
          "guest_advance" => method.guest_advance.to_s,
          "default_cash" => method.default_cash.to_s,
          "active" => method.active?.to_s,
          "surcharge_enabled" => method.surcharge?.to_s,
          "surcharge_posting_type" => method.surcharge_posting_type,
          "surcharge_value" => method.surcharge_value&.to_s,
          "surcharge_extra_charge_id" => method.surcharge_extra_charge_id&.to_s
        }
      end
      return adopted if adopted.any?

      suggested_payment_method_entries
    end

    def suggested_payment_method_entries
      cash_claimed = false
      current_hotel.transaction_codes
                   .where(system_key: PaymentMethods::EnsureDefaults::SYSTEM_KEYS)
                   .where.missing(:hotel_payment_method)
                   .order(:code)
                   .map do |code|
        cash = code.system_key == "cash_payment"
        default_cash = cash && !cash_claimed
        cash_claimed ||= default_cash
        {
          "transaction_code_id" => code.id.to_s,
          "client_key" => "suggested-#{code.system_key}",
          "locked" => code.system_required?.to_s,
          "name" => code.name,
          "code" => code.code,
          "payment_method_type" => cash ? "cash" : "bank_gateway",
          "guest_advance" => (code.category == "booking_payment").to_s,
          "default_cash" => default_cash.to_s,
          "active" => "true",
          "surcharge_enabled" => "false"
        }
      end
    end

    # What "only the charges I choose" may name: the things the property sells,
    # not the room and its own charges — those are what the scope above this
    # picker already means.
    #
    # A code a discount already pins stays on the list even when it is one of
    # those. The settings portal can target anything the join row accepts, and a
    # picker that cannot show a selection would drop it on the next save.
    def discount_charge_code_choices
      pinned = @discount_entries.flat_map { |entry| Array(entry["applicable_transaction_code_ids"]) }
                                .map(&:to_s).to_set

      current_hotel.transaction_codes.active.discountable.order(:code)
                   .reject { |code| code.category.in?(TransactionCode::ROOM_CATEGORIES) && pinned.exclude?(code.id.to_s) }
                   .map { |code| { label: "#{code.name} (#{code.code})", value: code.id.to_s } }
    end

    def persisted_discount_entries
      adopted = current_hotel.hotel_discounts.includes(:transaction_code, :applicable_transaction_codes).ordered.map do |discount|
        {
          "id" => discount.id.to_s,
          "client_key" => "discount-#{discount.id}",
          "name" => discount.name,
          "code" => discount.code,
          "pricing_type" => discount.pricing_type,
          "rate_value" => discount.rate_value&.to_s,
          "application_scope" => discount.application_scope,
          "applicable_transaction_code_ids" => discount.applicable_transaction_codes.map { |code| code.id.to_s }
        }
      end
      return adopted if adopted.any? || @presenter.read_only?

      suggested_discount_entries
    end

    def suggested_discount_entries
      current_hotel.transaction_codes
                   .where(kind: "adjustment", category: "discount")
                   .where.missing(:hotel_discount)
                   .order(:code)
                   .map do |code|
        {
          "transaction_code_id" => code.id.to_s,
          "client_key" => "suggested-#{code.system_key}",
          "name" => code.name,
          "code" => code.code,
          "pricing_type" => "manual",
          "application_scope" => "all_eligible_charges",
          "applicable_transaction_code_ids" => []
        }
      end
    end

    # A property that has adopted nothing yet starts from the seeded revenue
    # codes rather than an empty table — but as unsaved rows, so the charges it
    # actually sells are the ones it saves. Removing a suggestion here simply
    # means never creating it.
    def persisted_extra_charge_entries
      adopted = current_hotel.hotel_extra_charges.includes(transaction_code: :transaction_code_taxes).ordered.map do |charge|
        {
          "id" => charge.id.to_s,
          "client_key" => "extra-charge-#{charge.id}",
          "name" => charge.name,
          "code" => charge.code,
          "rate_value" => (charge.rate_value&.to_s unless charge.percentage?),
          "charging_unit" => charge.charging_unit,
          "tax_rule_keys" => charge.transaction_code.tax_rule_keys
        }
      end
      return adopted if adopted.any?

      suggested_extra_charge_entries
    end

    def suggested_extra_charge_entries
      current_hotel.transaction_codes
                   .where(system_key: Financials::EnsureDefaultExtraCharges::SYSTEM_KEYS)
                   .where.missing(:hotel_extra_charge)
                   .order(:code)
                   .map do |code|
        {
          "transaction_code_id" => code.id.to_s,
          "client_key" => "suggested-#{code.system_key}",
          "name" => code.name,
          "code" => code.code,
          "charging_unit" => "per_item",
          "tax_rule_keys" => []
        }
      end
    end

    # The onboarding tax table submits the same row shape it renders, so a failed
    # save can hand back what the owner typed instead of what is stored.
    def persisted_tax_entries
      current_hotel.hotel_taxes.order(:created_at, :id).map do |tax|
        {
          "id" => tax.id.to_s,
          "name" => tax.name,
          "registration_number" => tax.registration_number,
          "charge_type" => tax.charge_type,
          "rate_type" => tax.rate_type,
          "amount" => tax.amount.to_s,
          "enabled" => tax.enabled.to_s,
          "foreign_guests_only" => tax.foreign_guests_only.to_s
        }
      end
    end

    def update_implemented_section
      return head :method_not_allowed if @current_entry.definition.key == "review"

      action = params.require(:navigation_action)
      return head :unprocessable_entity unless action.in?(%w[save_draft save_continue])

      complete = action == "save_continue"
      result =
        case @current_entry.definition.key
        when "property_profile"
          Onboarding::SavePropertyProfile.new(
            hotel: current_hotel,
            params: params,
            actor: current_user,
            complete: complete
          ).call
        when "property_photos"
          Onboarding::SavePropertyPhotos.new(
            hotel: current_hotel,
            actor: current_user,
            complete: complete
          ).call
        when "roles_permissions"
          save_role_review(complete)
        when "staff_setup"
          Onboarding::SaveStaffDrafts.new(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:staff_entries] || {},
            complete: complete
          ).call
        when "taxes_fees"
          Onboarding::SaveTaxesFees.new(
            hotel: current_hotel,
            actor: current_user,
            params: params,
            confirmed: params[:confirm_taxes],
            complete: complete
          ).call
        when "room_revenue"
          Onboarding::SaveRoomRevenue.new(
            hotel: current_hotel,
            actor: current_user,
            params: params,
            complete: complete
          ).call
        when "rooms"
          Onboarding::SaveRooms.new(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:room_entries] || {},
            complete: complete
          ).call
        when "rates_availability"
          Onboarding::SaveRatesAvailability.call(
            hotel: current_hotel,
            actor: current_user,
            params: params,
            complete: complete
          )
        when "extra_charges"
          Onboarding::SaveExtraCharges.call(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:extra_charge_entries] || {},
            complete: complete
          )
        when "discounts"
          Onboarding::SaveDiscounts.call(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:discount_entries] || {},
            complete: complete
          )
        when "payment_methods"
          Onboarding::SavePaymentMethods.call(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:payment_method_entries] || {},
            complete: complete
          )
        when "corporate_accounts"
          Onboarding::SaveCorporateDrafts.call(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:corporate_draft_entries] || {},
            complete: complete
          )
        when "channel_manager"
          Onboarding::SaveOtaCredentials.call(
            hotel: current_hotel,
            actor: current_user,
            entries: params[:ota_credential_entries] || {},
            complete: complete
          )
        end

      return render_section_error(result) unless result.success?

      build_navigation
      destination = complete ? (@navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)) : @navigation.fetch(@current_entry.definition.key)
      notice = complete ? "Progress saved. Continue with the next step." : "Draft saved."
      redirect_to onboarding_path(destination), notice: notice
    end

    def save_role_review(complete)
      if complete
        Onboarding::ConfirmRolePresets.new(
          hotel: current_hotel,
          actor: current_user,
          confirmed: params[:confirm_presets]
        ).call
      else
        update_section("in_progress", source: "role_preset_review")
      end
    end

    def render_section_error(result)
      current_hotel.assign_attributes(property_profile_params) if @current_entry.definition.key == "property_profile"
      build_navigation
      @current_entry = @navigation.fetch(@current_entry.definition.key)
      prepare_section(entries: result.respond_to?(:entries) ? result.entries : nil)
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_content
    end

    def property_profile_params
      return {} unless params[:hotel]

      params.require(:hotel).permit(
        :name, :description, :address, :city, :country, :star_rating,
        :google_map_link, :contact_email, :contact_phone, :fixed_line_number, :whatsapp_number,
        :time_zone, :default_currency, :tin, :ssm_number, amenities: []
      )
    end

    def persisted_room_entries
      current_hotel.room_types.order(:created_at, :id).map do |room_type|
        {
          "id" => room_type.id.to_s,
          "client_key" => "room-#{room_type.id}",
          "name" => room_type.name,
          "max_adults" => room_type.max_adults.to_s,
          "max_children" => room_type.max_children.to_s,
          "quantity" => room_type.quantity.to_s,
          "no_smoking" => (!room_type.smoking_allowed?).to_s,
          "no_pets" => (!room_type.pets_allowed?).to_s,
          "amenities" => room_type.amenities,
          "room_number_mode" => room_type.room_number_mode,
          "room_numbers" => room_type.room_numbers
        }
      end
    end

    def prepare_rates_availability(entries: nil)
      @rate_rooms = current_hotel.room_types.includes(
        :room_inventories,
        :rate_plans,
        room_type_rate_plans: [ :occupancy_prices, :age_band_prices, { rate_plan: :rate_plan_age_bands } ]
      ).order(:created_at, :id).to_a
      @custom_rate_plans = current_hotel.rate_plans.active.where(kind: "custom").includes(
        :booking_rooms, :rate_plan_age_bands,
        room_type_rate_plans: [ :occupancy_prices, :age_band_prices, :room_type ]
      ).order(:created_at, :id).to_a
      @rates_start_date = Date.current
      @rates_end_date = Date.current + 364.days
      @standard_rate_entries = @rate_rooms.map { |room| standard_rate_entry(room) }
      @custom_rate_entries = @custom_rate_plans.map { |plan| custom_rate_entry(plan) }
      @availability_entries = @rate_rooms.map { |room| availability_entry(room) }
      @child_bands = child_band_entries
      @new_rate_plan_entry = new_custom_rate_entry
      @weekend_uplift = { "adjustment_mode" => "percent", "adjustment_value" => "0" }
      @rates_coverage = Rates::SetupCoverage.call(
        hotel: current_hotel,
        start_date: @rates_start_date,
        end_date: @rates_end_date
      )

      return unless entries.present?

      submitted = entries.respond_to?(:to_unsafe_h) ? entries.to_unsafe_h : entries.to_h
      @rates_start_date = submitted["start_date"].to_date if submitted["start_date"].present?
      @rates_end_date = submitted["end_date"].to_date if submitted["end_date"].present?
      @standard_rate_entries = submitted_collection(submitted["standard_entries"]) if submitted["standard_entries"].present?
      @custom_rate_entries = submitted_collection(submitted["custom_plans"]) if submitted["custom_plans"].present?
      @availability_entries = submitted_collection(submitted["availability_entries"]) if submitted["availability_entries"].present?
      @child_bands = submitted_collection(submitted["child_bands"]) if submitted["child_bands"].present?
      @weekend_uplift = @weekend_uplift.merge(submitted["weekend_uplift"].to_h.stringify_keys) if submitted["weekend_uplift"].present?
    end

    # Band prices keyed by the band's position, matching the column order the
    # table renders and the order the save path reads back.
    def age_band_price_entry(assignment, plan)
      return {} unless current_hotel.sells_per_person?

      prices = plan&.rate_plan_age_bands.to_a.each_with_index.to_h do |band, index|
        room_price = assignment&.age_band_price_for(band)
        # Existing flat bands predate room-specific prices. Showing their
        # amount here lets the first onboarding save carry that value forward.
        room_price ||= band.price_value if room_price.nil? && band.amount?
        [ index.to_s, room_price&.to_s ]
      end

      { "age_band_prices" => prices.compact }
    end

    # What this room includes on this plan. Reads through the pairing so a row
    # shows the figure that will actually price it, whether the pairing carries
    # its own or is still deferring to the plan.
    def occupancy_rule_entry(assignment, plan)
      RoomTypeRatePlan::OCCUPANCY_RULES.index_with do |rule|
        value = assignment&.public_send(:"effective_#{rule}") || plan&.public_send(rule)
        value&.to_s
      end.stringify_keys
    end

    # Bands are one property-wide policy stored per plan, so any plan answers for
    # all of them. Standard is the anchor because it always exists.
    def child_band_entries
      return [] unless current_hotel.sells_per_person?

      anchor = @rate_rooms.filter_map { |room| room.standard_rate_plan }.first
      bands = anchor&.rate_plan_age_bands.to_a
      return default_child_band_entries if bands.empty?

      bands.map { |band| band.attributes.slice("min_age", "max_age", "label", "pricing_mode") }
    end

    def default_child_band_entries
      [
        { "min_age" => RatePlanAgeBand::AGE_RANGE.min, "max_age" => 2, "label" => "Infant", "pricing_mode" => "amount" },
        { "min_age" => 3, "max_age" => RatePlanAgeBand::REQUIRED_AGE_RANGE.max, "label" => "Child", "pricing_mode" => "amount" }
      ]
    end

    def standard_rate_entry(room)
      plan = room.standard_rate_plan
      assignment = room.room_type_rate_plans.find { |item| item.rate_plan_id == plan&.id }
      pricing = HotelPortal::RatePlanRoomPricing.from_assignment(
        assignment, room_type: room, sells_per_person: current_hotel.sells_per_person?
      )
      pricing.default_rate = room.base_price unless current_hotel.sells_per_person?
      { "name" => plan&.name }
        .merge(occupancy_rule_entry(assignment, plan))
        .merge(age_band_price_entry(assignment, plan))
        .merge("room_type_id" => room.id.to_s, "room_name" => room.name)
        .merge(pricing.to_h)
    end

    # A custom plan covers every room category, so the rows are built from the
    # property's rooms rather than from whatever happens to be attached. An
    # unattached room shows up as an empty row waiting for a price.
    def custom_rate_entry(plan)
      attached = plan.room_type_rate_plans.index_by(&:room_type_id)
      pricings = @rate_rooms.map do |room|
        [ room, attached[room.id], HotelPortal::RatePlanRoomPricing.from_assignment(
          attached[room.id], room_type: room, sells_per_person: current_hotel.sells_per_person?
        ) ]
      end

      # Pricing basis is one decision for the plan. It is still stored per
      # assignment, so the first attached room answers for the group heading.
      basis = pricings.find { |_room, assignment, _pricing| assignment }&.last

      {
        "name" => plan.name,
        "id" => plan.id.to_s,
        "client_key" => "plan-#{plan.id}",
        "deletable" => plan.deletable?,
        "rate_mode" => basis&.rate_mode || "manual",
        "derive_mode" => basis&.derive_mode || "multiplier",
        "derive_value" => basis&.derive_value.to_s,
        "assignments" => pricings.map do |room, assignment, pricing|
          {
            "id" => assignment&.id.to_s,
            "client_key" => "assignment-#{room.id}",
            "room_type_id" => room.id.to_s
          }.merge(occupancy_rule_entry(assignment, plan))
           .merge(age_band_price_entry(assignment, plan))
           .merge(pricing.to_h)
        end
      }
    end

    # A new plan starts from what each room already includes on Standard, so the
    # operator adjusts prices rather than re-entering occupancy rules they have
    # just finished setting a row above.
    def new_custom_rate_entry
      {
        "client_key" => "PLAN_KEY",
        "rate_mode" => "manual",
        "assignments" => @rate_rooms.map do |room|
          standard = room.standard_rate_plan
          assignment = room.room_type_rate_plans.find { |item| item.rate_plan_id == standard&.id }
          { "client_key" => "assignment-#{room.id}", "room_type_id" => room.id.to_s }
            .merge(occupancy_rule_entry(assignment, standard))
        end
      }
    end

    def availability_entry(room)
      inventory = room.room_inventories.find { |item| item.date == @rates_start_date }
      {
        "room_type_id" => room.id.to_s,
        "room_name" => room.name,
        "quantity" => (inventory&.quantity || room.quantity).to_s,
        "status" => inventory&.status || "open"
      }
    end

    def submitted_collection(value)
      (value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : value.to_h.values).map(&:deep_stringify_keys)
    end

    def update_placeholder_section
      case params.require(:navigation_action)
      when "save_draft" then save_draft
      when "save_continue" then save_and_continue
      when "skip" then skip_section
      else head :unprocessable_entity
      end
    end

    def save_draft
      unless @current_entry.record.resolved?
        result = update_section("in_progress", source: "onboarding_shell")
        return redirect_result_error(result) unless result.success?
      end

      redirect_to onboarding_path(@current_entry), notice: "Draft saved."
    end

    def save_and_continue
      result = update_section("complete", source: "onboarding_shell", placeholder: true)
      return redirect_result_error(result) unless result.success?

      build_navigation
      destination = @navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)
      redirect_to onboarding_path(destination), notice: "Progress saved. Continue with the next step."
    end

    def skip_section
      result = update_section("skipped", source: "onboarding_shell")
      return redirect_result_error(result) unless result.success?

      build_navigation
      destination = @navigation.next_entry(@current_entry.definition.key) || @navigation.fetch(@current_entry.definition.key)
      notice = @current_entry.definition.key == "staff_setup" ? "No additional staff will be invited for now." : "Step skipped for now."
      redirect_to onboarding_path(destination), notice: notice
    end

    def update_section(state, metadata)
      Onboarding::UpdateSection.new(
        hotel: current_hotel,
        section_key: @current_entry.definition.key,
        state: state,
        actor: current_user,
        metadata: metadata
      ).call
    end

    def preset_roles
      current_hotel.account.roles.where(slug: Onboarding::ConfirmRolePresets::PRESET_SLUGS)
                   .order(Arel.sql("CASE slug WHEN 'hotel_owner' THEN 0 WHEN 'general_manager' THEN 1 WHEN 'front_desk' THEN 2 WHEN 'housekeeper' THEN 3 ELSE 4 END"))
    end

    def implemented_section?
      @current_entry.definition.key.in?(IMPLEMENTED_SECTIONS)
    end

    def redirect_result_error(result)
      redirect_to onboarding_path(@current_entry), alert: result.error
    end

    def redirect_read_only
      redirect_to onboarding_path(@current_entry), alert: "Onboarding is read-only while this property is pending review."
    end

    def pending_review?
      current_hotel.status == "pending_review"
    end

    def onboarding_path(entry)
      hotel_onboarding_section_path(current_hotel, section_key: entry.definition.route_name)
    end
  end
end
