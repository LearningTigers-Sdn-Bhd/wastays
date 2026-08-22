module AiConcierge
  module Orchestration
    module Booking
      class CompletionHandler
        include Responses

        def initialize(hotel:, prospect:, phone:)
          @hotel = hotel
          @prospect = prospect
          @phone = phone.to_s.presence
        end

        def call(conversation_state:, active_branch:)
          selected_option = active_branch["confirmation_candidate"] || active_branch["selected_option"]
          return booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :invalid_selection, pending_question: "select_option") unless selected_option

          selected_rate_plan = selected_option&.dig("selected_rate_plan") || {}
          result = Tools::Booking::GenerateBookingUrlTool.new(
            hotel: hotel,
            selected_option: selected_option,
            guest_phone: phone || prospect.phone_number,
            rate_plan_id: selected_rate_plan["rate_plan_id"]
          ).call
          return quote_failure_response(conversation_state: conversation_state, active_branch: active_branch, error: result["error"]) unless result["success"]

          active_branch["selected_option"] = selected_option
          active_branch["confirmation_candidate"] = nil
          payload = booking_payload(conversation_state, active_branch, pending_question: nil, status: "completed")
          payload = State::ConversationTaskManager.new(slots_payload: payload).archive_completed_booking

          Core::DomainResponse.new(
            slots_payload: payload,
            reply_type: :booking_link_ready,
            extra_context: { result: result.merge("selected_option" => selected_option) },
            flow_status: "ended",
            end_reason: "booking_url_generated"
          )
        end

        private

        attr_reader :hotel, :prospect, :phone

        # A quote that failed to generate still owes the guest a sentence.
        #
        # This used to hand a payload straight back to the caller, skipping the
        # persister -- survivable on the API path, which renders whatever it is
        # given, but `Concierge::AnswerWebMessageJob` reads only `success?` and
        # throws the payload away. A web guest therefore watched their "yes"
        # vanish into silence at the one moment money was involved.
        #
        # The thread stays on `confirm_selection` with the candidate intact:
        # the failure is the hotel's, not the guest's, so "yes" should still
        # work when they try again.
        #
        # It now counts as a re-ask too, along with everything else that comes
        # through `Responses`. That is redundant here on purpose -- the flag
        # below already puts the thread in front of staff on the first failure,
        # where the counter would take three -- but a path that quietly opted
        # out of counting is what made the four copies of this method worth
        # merging, so it does not opt out again.
        def quote_failure_response(conversation_state:, active_branch:, error:)
          booking_response(
            conversation_state: conversation_state,
            active_branch: active_branch,
            reply_type: nil,
            pending_question: "confirm_selection",
            extra_context: { message: error },
            action_name: nil
          ).with(needs_human_support: true)
        end
      end
    end
  end
end
