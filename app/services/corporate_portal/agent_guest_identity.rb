# frozen_string_literal: true

module CorporatePortal
  # The one "IC / Passport" field an agent fills in, routed into the Guest
  # columns it belongs in. Shared by booking creation and the pre-arrival guest
  # edit so both file identity numbers the same way.
  module AgentGuestIdentity
    private

    # Routes the one "IC / Passport" field the agent actually sees into
    # whichever column Guest validates against. A Malaysian's IC drives
    # document_type and, from there, lets Guest derive date of birth straight
    # from the number (see Guest#populate_date_of_birth_from_malaysian_ic) --
    # a passport number carries no such date, so nothing is inferred from it.
    def identity_attributes(country:, id_number:)
      id_number = id_number.presence
      return {} if id_number.blank? || country.blank?

      if country.to_s.casecmp?("Malaysia")
        malaysian_ic_attributes(id_number)
      else
        # The field allows headroom (20 characters) for spaces, hyphens or a
        # check digit an agent might type or paste in -- none of them are part
        # of the number itself, so they are stripped here rather than kept as
        # noise in what gets filed against the guest.
        { document_type: "passport", passport_number: id_number.gsub(/[\s-]/, "") }
      end
    end

    # The form's own script blocks a malformed IC before it can be submitted
    # (agent_guest_identity_controller.js), but that is a client the request
    # does not have to go through -- so this is the one place a stray letter
    # actually stops it. Filed as-is under government_id either way (it is
    # still a Malaysian identity number field), but document_type is only set
    # to "malaysian_nric" for something that looks like a real one: setting it
    # for "9902031z26661zz" would let Guest derive a date of birth off digits
    # a letter had silently fallen out of (see
    # Guests::MalaysianIcDateOfBirthParser, which reads the same way).
    def malaysian_ic_attributes(id_number)
      return { government_id: id_number } unless id_number.match?(/\A[\d\s-]+\z/)

      { document_type: "malaysian_nric", government_id: id_number }
    end
  end
end
