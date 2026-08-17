# frozen_string_literal: true

module Onboarding
  class SavePropertyProfile
    Result = ApplicationResult.define(:section)
    REQUIRED_FIELDS = {
      name: "Property name",
      address: "Address",
      city: "City",
      country: "Country",
      time_zone: "Timezone",
      contact_email: "Contact email",
      contact_phone: "Contact phone",
      default_currency: "Default currency"
    }.freeze

    def initialize(hotel:, params:, actor:, complete:)
      @hotel = hotel
      @params = params
      @actor = actor
      @complete = complete
    end

    def call
      return failure("Enter a valid contact email address.") unless valid_contact_email?
      return failure("Select a valid timezone.") unless valid_time_zone?

      return failure(save_profile_error) unless save_profile

      if @complete && missing_requirements.any?
        return failure("Complete the required property details: #{missing_requirements.to_sentence}.")
      end

      transition(@complete ? "complete" : "in_progress")
    end

    private

    def save_profile
      success = false
      @save_profile_error = nil

      Hotel.transaction do
        saved = HotelPortal::ProfileForm.new(@hotel, ActionController::Parameters.new(hotel: profile_attributes)).save
        unless saved
          @save_profile_error = @hotel.errors.full_messages.to_sentence
          raise ActiveRecord::Rollback
        end

        if operating_attributes.present?
          @hotel.assign_attributes(operating_attributes)
          unless @hotel.save
            @save_profile_error = @hotel.errors.full_messages.to_sentence
            raise ActiveRecord::Rollback
          end
        end

        if policy_attributes.present?
          policy = @hotel.property_policy || @hotel.build_property_policy
          policy.assign_attributes(policy_attributes)
          unless policy.save
            @save_profile_error = policy.errors.full_messages.to_sentence
            raise ActiveRecord::Rollback
          end
        end
        success = true
      end
      success
    end

    def save_profile_error
      @save_profile_error.presence || "Property profile could not be saved."
    end

    def profile_attributes
      @params.require(:hotel).permit(
        :name, :description, :address, :city, :country, :star_rating,
        :google_map_link, :contact_email, :contact_phone, :fixed_line_number, :whatsapp_number,
        :time_zone, :default_currency, :tin, :ssm_number,
        :local_government_name, :local_government_license_number, amenities: []
      )
    end

    # The business day window lives on the hotel itself, so it is saved beside the
    # profile rather than through ProfileForm, which only owns guest-facing details.
    def operating_attributes
      @params.require(:hotel).permit(:business_starts_at, :business_ends_at).compact_blank
    end

    def policy_attributes
      return {} unless @params[:property_policy]

      @params.require(:property_policy).permit(:check_in_time, :check_out_time)
    end

    def valid_contact_email?
      email = profile_attributes[:contact_email].to_s
      email.blank? || email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def valid_time_zone?
      zone = profile_attributes[:time_zone].to_s
      zone.blank? || ActiveSupport::TimeZone[zone].present?
    end

    def missing_requirements
      missing = REQUIRED_FIELDS.filter_map { |attribute, label| label if @hotel.public_send(attribute).blank? }
      policy = @hotel.property_policy
      missing << "Check-in time" if policy&.check_in_time.blank?
      missing << "Check-out time" if policy&.check_out_time.blank?
      missing
    end

    def transition(state)
      result = UpdateSection.new(
        hotel: @hotel,
        section_key: "property_profile",
        state: state,
        actor: @actor,
        metadata: { source: "property_profile" }
      ).call
      return Result.failure(result.error, section: result.section) unless result.success?

      Result.success(section: result.section)
    end

    def failure(message)
      Result.failure(message.presence || "Property profile could not be saved.", section: @hotel.onboarding_sections.find_by(section_key: "property_profile"))
    end
  end
end
