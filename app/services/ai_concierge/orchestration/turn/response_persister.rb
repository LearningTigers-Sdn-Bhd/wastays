module AiConcierge
  module Orchestration
    module Turn
      class ResponsePersister
        UNSTYLED_REPLY_TYPES = %i[
          booking_attempt_cancelled_next_step
          booking_support_requested
          booking_cancellation_support_requested
        ].freeze
        # The thread is required, not optional: every reply this writes is a row
        # in it, and the column no longer takes a message without one.
        def initialize(hotel:, conversation:, message: nil)
          @hotel = hotel
          @conversation = conversation
          @message = message.to_s
        end

        def persist_response(prospect:, conversation_state:, slots_payload:, reply_type:, active_topic:, active_flow:, pending_question:, action_name:, extra_context: {}, flow_status: nil, end_reason: nil, needs_human_support: false)
          messenger_context = { reply_type: reply_type, opening_reply: opening_reply?, language: conversation.reply_language }.merge(extra_context)
          reply_message = Agents::MessengerAgent.new(hotel: hotel, context: messenger_context).call.fetch("reply_message")
          persist_static_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            reply_message: reply_message,
            needs_human_support: needs_human_support,
            action_name: action_name,
            active_topic: active_topic,
            active_flow: active_flow,
            pending_question: pending_question,
            flow_status: flow_status,
            end_reason: end_reason,
            knowledge_reply: extra_context[:knowledge_reply],
            guest_language: extra_context[:guest_language],
            protected_names: extra_context[:protected_names],
            skip_styling: UNSTYLED_REPLY_TYPES.include?(reply_type&.to_sym)
          )
        end

        def persist_domain_response(prospect:, conversation_state:, domain_result:)
          persist_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: domain_result.slots_payload,
            reply_type: domain_result.reply_type,
            active_topic: domain_result.active_topic,
            active_flow: domain_result.active_flow,
            pending_question: domain_result.pending_question,
            action_name: domain_result.action_name,
            extra_context: domain_result.extra_context,
            flow_status: domain_result.flow_status,
            end_reason: domain_result.end_reason,
            needs_human_support: domain_result.needs_human_support
          )
        end

        # `needs_human_support` used to travel out in the API payload and stop
        # there: a booking that could not be quoted, or a question the guest had
        # now failed to answer three times, reached whatever the relay decided
        # to do with a flag -- and on the web chat, nobody at all. This is the
        # one place holding both the flag and the thread, so this is where the
        # thread is put in front of staff. `request_human!` deliberately leaves
        # `mode` alone: the bot keeps answering until a person actually arrives.
        def persist_static_response(prospect:, conversation_state:, slots_payload:, reply_message:, needs_human_support:, action_name:, active_topic:, active_flow:, pending_question:, flow_status:, end_reason:, knowledge_reply: false, guest_language: nil, protected_names: nil, skip_styling: false)
          reply = style(reply_message, knowledge_reply: knowledge_reply, guest_language: guest_language, protected_names: protected_names, skip_styling: skip_styling)
          ActiveRecord::Base.transaction do
            persist_state(conversation_state, slots_payload:, active_topic:, active_flow:, pending_question:, flow_status:, end_reason:)
            record_outbound_message(prospect, reply)
            conversation.request_human! if needs_human_support
          end
          Core::ResponsePayloadBuilder.new(reply_message: reply.body, needs_human_support: needs_human_support, action_name: action_name, prospect_public_id: prospect.public_id).call
        end

        private

        attr_reader :hotel, :conversation, :message

        # Whether the assistant has said anything in this thread yet. Read
        # before the reply being built is written, so the reply that answers a
        # guest's opening message is the one that sees true.
        def opening_reply? = conversation.messages.where(direction: "outbound").none?

        # What the guest is sent, and -- only when a rewrite replaced it -- what
        # the hotel's own code had written.
        Reply = Struct.new(:body, :source_body, keyword_init: true)

        # The hotel's tone and the guest's language, applied once, here.
        #
        # Every reply the assistant has ever sent passes through this method --
        # the builders above and the four control replies that arrive with their
        # sentence already written -- which is why it is the only place that
        # knows how the hotel sounds.
        #
        # It runs on a finished string. Nothing the model returns can change a
        # price, a date or a link, because those were computed before it was
        # asked, and anything it did change is caught below.
        def style(template, knowledge_reply: false, guest_language: nil, protected_names: nil, skip_styling: false)
          return Reply.new(body: template) if template.blank?
          return Reply.new(body: template) if skip_styling
          if knowledge_reply
            conversation.record_language!(guest_language)
            return Reply.new(body: template)
          end

          # Read once, before the stylist runs and before anything records over
          # it: this is the language the reply is owed unless the guest's own
          # message establishes a new one, and both the instruction sent down
          # and the check made afterwards have to mean the same thing by it.
          thread_language = conversation.reply_language
          return Reply.new(body: template) unless Agents::ReplyStylist.styles?(hotel: hotel, thread_language: thread_language, guest_message: message)

          styled = Agents::ReplyStylist.new(
            hotel: hotel, template: template, guest_message: message, thread_language: thread_language
          ).call
          text = verified(template, styled, thread_language: thread_language, protected_names: protected_names)

          text ? Reply.new(body: text, source_body: template) : Reply.new(body: template)
        rescue Agents::ReplyStylist::ReplyStylistError => e
          Rails.logger.warn("AiConcierge::ReplyStylist skipped: #{e.message}")
          Reply.new(body: template)
        end

        # A rewrite the verifier rejects is not repaired and not retried: the
        # template says the same thing correctly, and the guest is waiting.
        #
        # The language is recorded either way. What the guest wrote in is a fact
        # about the guest, not about whether this particular rewrite came back
        # usable, and forgetting it would ask the same question again next turn.
        #
        # What gets recorded is the language the model read in the *guest's*
        # message, and never the one it reports having written in. The second is
        # a claim about its own output, and recording it made the thread's
        # language self-reinforcing: one wrong claim, and every later message
        # too short to carry a language of its own -- "yes", a row number --
        # was answered in a language the guest had never used. Correctly, too,
        # because by then the thread said so, and nothing could say otherwise.
        def verified(template, styled, thread_language:, protected_names: nil)
          conversation.record_language!(styled.guest_language)
          return rejected(:language) unless wrote_in_the_decided_language?(styled, thread_language)

          checker = Agents::RewriteVerifier.new(
            template: template,
            candidate: normalized_styled_text(styled.text, protected_names),
            protected_names: protected_names_for(protected_names)
          )
          checker.call || rejected(checker.failure)
        end

        def normalized_styled_text(text, extra_names)
          Agents::PunctuationNormalizer.call(text, protected_names: protected_names_for(extra_names))
        end

        # Ruby decided which language this reply had to go out in; this is the
        # only thing that checks the model did as it was told.
        #
        # It compares the two labels rather than reading the text, so it catches
        # a model that changed language and said so, and not one that drifted
        # without noticing. That is the half of the problem available for
        # nothing, and rejecting costs nothing either -- the template is already
        # correct, and already in the language the thread was in.
        def wrote_in_the_decided_language?(styled, thread_language)
          styled.language == (styled.guest_language.presence || thread_language)
        end

        def rejected(reason)
          Rails.logger.warn("AiConcierge::ReplyStylist rejected (#{reason}) for conversation #{conversation.id}")
          nil
        end

        # The words the guest will type back at us. Fetched once per turn, and
        # only on a turn the stylist actually runs on.
        def protected_names_for(extra_names)
          @protected_names ||= [ hotel.name ] + hotel.room_types.pluck(:name) + hotel.rate_plans.pluck(:name)
          @protected_names + Array(extra_names)
        end

        def persist_state(conversation_state, slots_payload:, active_topic:, active_flow:, pending_question:, flow_status: nil, end_reason: nil)
          patch = State::StatePatchBuilder.new(
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            active_topic: active_topic,
            active_flow: active_flow,
            pending_question: pending_question,
            flow_status: flow_status || (active_flow.present? ? "active" : "completed"),
            end_reason: end_reason,
            now: Time.current
          ).call
          conversation_state.update!(patch)
        end

        # `sender_role` is stated rather than left to the direction default: once
        # staff can reply, "outbound" stops implying the bot wrote it, and a
        # message that guessed its own author would be wrong from that day on.
        def record_outbound_message(prospect, reply)
          prospect&.prospect_messages&.create!(
            conversation: conversation,
            direction: "outbound",
            sender_role: "bot",
            body: reply.body,
            source_body: reply.source_body
          )
          prospect&.touch_last_contact!
        end
      end
    end
  end
end
