# frozen_string_literal: true

# Takes a signed-in guest from the portal straight into the stay page of one
# of their bookings.
#
# The stay page usually asks a new browser for the confirmation code. A
# portal guest has already proved who they are, and the booking came through
# current_guest.bookings, so the code would only ask the same thing again.
#
# Fails when the stay has no stay page yet (a future stay) or no longer has
# one (after the grace period). The caller sends the guest to the public
# concierge home then.
class Guest::OpenConcierge
  Result = ApplicationResult.define(:stay_access, :expires_at)

  def initialize(booking:, now: Time.current)
    @booking = booking
    @now = now
  end

  def call
    eligibility = Concierge::StayAccess::Eligibility.new(booking: @booking, now: @now).call
    return Result.failure(eligibility.error) unless eligibility.success?

    ensured = Concierge::StayAccess::Ensure.new(booking: @booking, now: @now).call
    return Result.failure(ensured.error) unless ensured.success?

    Result.success(stay_access: ensured.stay_access, expires_at: eligibility.expires_at)
  end
end
