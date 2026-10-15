# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      # Decomposes one guest message, then lets application services answer it.
      class HandleGuestTurnFunction < BaseFunction
        QUESTION_KINDS = %w[hotel_information hotel_policy room_information nearby_attractions].freeze
        COMMERCIAL_INTENTS = %w[none price_exploration booking].freeze
        SUPPORT_TRIGGERS = %w[emergency guest_asks_for_person complaint payment_question].freeze
        PAYMENT_POLICY = /\b(?:policy|policies|payment methods?|ways? to pay|cards? (?:do you )?accept|accepted cards?|deposit policy|pay at (?:the )?hotel)\b/i
        GUEST_PAYMENT = /\b(?:my|me|i|we|our)\b.*\b(?:payment|bill|billing|charge|folio|refund)\b|\b(?:charged|refunded|overcharged|double[ -]charged)\b/i

        description <<~DESCRIPTION
          Handle every hotel-information, room-information, attraction, price,
          availability and new-booking message. Call this tool exactly once.

          Put every hotel question in questions, in the guest's original order.
          There is no question-count limit. Copy each evidence value exactly
          from the guest's message. Use the commercial section for every price,
          availability or booking request in the same message. Use intent none
          when the message contains only hotel questions.

          Put complaints, emergencies, requests for a person and guest-specific
          payment, bill, charge, folio or refund problems in support_requests.
          A general question about payment or cancellation policy is a hotel
          question, not a support request. Do not use this tool for an
          existing-booking request or cancellation; the application handles
          those before you run.
        DESCRIPTION

        parameters do
          array :questions do
            object do
              string :evidence, description: "Exact words copied from the guest's message"
              string :label, description: "A short display label"
              string :kind, enum: QUESTION_KINDS
              string :category, enum: %w[policy general_info faq]
              string :search_terms
              string :fact, enum: Retrieval::QueryHints::FACTS
              string :scope, enum: %w[specific broad]
              string :room_type_name
            end
          end
          array :support_requests do
            object do
              string :evidence, description: "Exact words copied from the guest's message"
              string :trigger, enum: SUPPORT_TRIGGERS
            end
          end
          string :guest_language, description: "ISO 639-1 code for the guest's language"
          object :commercial do
            string :intent, enum: COMMERCIAL_INTENTS
            object :slots do
              integer :target_month
              integer :target_year
              string :month_segment, enum: %w[early mid late]
              integer :nights
              integer :days
              integer :party_size_total
              integer :adults
              integer :children
              integer :room_count
              string :option_number
              string :confirmation, enum: %w[yes no]
              string :check_in
              string :check_out
              string :room_type_name
              string :option_action, enum: %w[details continue]
            end
            object :evidence do
              string :timing
              string :checkout
              string :duration
              string :party
            end
            object :signals do
              boolean :is_reset
              boolean :is_correction
              boolean :starts_new_booking_branch
            end
          end
        end

        def execute(questions: [], support_requests: [], guest_language: nil, commercial: nil)
          items = Array(questions).map(&:deep_stringify_keys)
          support_items = Array(support_requests).map(&:deep_stringify_keys)
          items, support_items = normalize_payment_policy(items, support_items)
          values = commercial.is_a?(Hash) ? commercial.deep_stringify_keys : { "intent" => "none" }
          if rate_question? && values["intent"].to_s == "none"
            items = []
            values = { "intent" => "price_exploration", "slots" => {}, "signals" => {}, "evidence" => {} }
          end
          return reject_invalid_turn unless valid_turn?(items, support_items, values)

          if (decision = immediate_escalation(support_items))
            return record(escalation_response(decision), digest: { escalated: decision.trigger })
          end

          if items.empty? && values["intent"].to_s == "none"
            return support_not_escalated_response(support_items)
          end

          if items.empty?
            return advance_booking(values)
          end

          answers = items.map { |item| resolve(item) }
          body = organized_answer(items, answers)
          information_result = information_response(items, answers, body)
          booking_result = booking_response(values)
          domain_result = booking_result ? merge_information_result(booking_result, information_result) : information_result
          combined_booking_reply = booking_result.present?
          body = information_result.extra_context[:message]
          body = append_booking_response(body, booking_result) if combined_booking_reply
          body = Orchestration::HotelKnowledge::Localizer.new(
            hotel: hotel,
            reply: body,
            language: guest_language.presence || context.thread_language
          ).call

          domain_result = domain_result.with(
            reply_type: combined_booking_reply ? nil : domain_result.reply_type,
            extra_context: domain_result.extra_context.merge(
              message: body,
              knowledge_reply: true,
              guest_language: guest_language
            )
          )
          record_knowledge_diagnostics(items, answers, domain_result)
          record(
            domain_result,
            digest: {
              answered: domain_result.extra_context[:knowledge_outcome] == "answered",
              question_count: items.length
            }
          )
        end

        private

        def valid_turn?(items, support_items, commercial)
          valid_questions = items.all? do |item|
            QUESTION_KINDS.include?(item["kind"]) &&
              item["label"].present? &&
              item["evidence"].present? &&
              context.message.include?(item["evidence"])
          end
          intent = commercial["intent"].presence || "none"
          valid_support = support_items.all? do |item|
            SUPPORT_TRIGGERS.include?(item["trigger"]) &&
              item["evidence"].present? && context.message.include?(item["evidence"])
          end
          valid_questions && COMMERCIAL_INTENTS.include?(intent) &&
            valid_support &&
            (items.present? || support_items.present? || intent != "none" || context.pending_question.present?)
        end

        def normalize_payment_policy(items, support_items)
          general_payment, remaining_support = support_items.partition do |item|
            item["trigger"] == "payment_question" && !guest_specific_payment?(item["evidence"])
          end
          general_payment.each do |item|
            next if items.any? { |question| question["evidence"] == item["evidence"] }

            items << {
              "evidence" => item["evidence"],
              "label" => "Payment policy",
              "kind" => "hotel_policy",
              "category" => "policy",
              "search_terms" => item["evidence"],
              "scope" => "specific"
            }
          end

          [ items, remaining_support ]
        end

        def guest_specific_payment?(evidence)
          text = evidence.to_s
          !text.match?(PAYMENT_POLICY) && text.match?(GUEST_PAYMENT)
        end

        def reject_invalid_turn
          domain_result = Orchestration::Core::DomainResponse.new(
            slots_payload: context.conversation_state.slots_payload,
            extra_context: { message: "Please send your request again in one message." }
          )
          record(domain_result, digest: { answered: false, reason: "invalid evidence" })
        end

        def immediate_escalation(support_items)
          support_items.each do |item|
            decision = Escalation::Policy.new(
              hotel: hotel,
              conversation: context.conversation,
              trigger: item["trigger"]
            ).call
            return decision if decision.handoff?
          end

          nil
        end

        def escalation_response(decision)
          Orchestration::Core::DomainResponse.new(
            slots_payload: context.conversation_state.slots_payload,
            next_action: Orchestration::Sales::NextAction.new("offer_front_desk"),
            needs_human_support: true,
            extra_context: {
              message: decision.message,
              escalation_trigger: decision.trigger,
              knowledge_outcome: "escalated"
            }
          )
        end

        def support_not_escalated_response(support_items)
          trigger = support_items.first&.fetch("trigger", nil)
          message = case trigger
          when "complaint"
            "I am sorry there is a problem. Please tell me what happened so I can help with the information available here."
          when "payment_question"
            "Please tell me which payment or charge you are asking about."
          else
            "Please tell me how I can help."
          end
          result = Orchestration::Core::DomainResponse.new(
            slots_payload: context.conversation_state.slots_payload,
            extra_context: { message: message, knowledge_outcome: "answered" }
          )
          record(result, digest: { answered: true, support_trigger: trigger })
        end

        def resolve(item)
          interpretation = interpretation_for(item)
          resolution = Orchestration::HotelKnowledge::QuestionResolver.new(
            hotel: hotel,
            message: item["evidence"],
            interpretation: interpretation,
            language: Conversation::DEFAULT_LANGUAGE,
            max_list_facts: item["kind"] == "nearby_attractions" ? 3 : nil,
            localize: false,
            fact_catalogue: fact_catalogue
          ).call
          resolution
        end

        def fact_catalogue
          @fact_catalogue ||= GuestContent::FactCatalogue.new(hotel: hotel).call
        end

        def interpretation_for(item)
          {
            "intent" => item["kind"],
            "topic" => topic_for(item),
            "scope" => item["scope"].presence,
            "slots" => { "room_type_name" => item["room_type_name"] }.compact,
            "retrieval_hints" => Retrieval::QueryHints.new(
              terms: item["search_terms"],
              fact: item["fact"],
              preferred_language: context.thread_language
            ).to_h
          }
        end

        def topic_for(item)
          case item["kind"]
          when "hotel_policy" then "hotel_policy"
          when "room_information" then "room_information"
          when "nearby_attractions" then "nearby_attractions"
          when "hotel_information"
            item["category"] == "faq" ? "hotel_faq" : "general_hotel_info"
          end
        end

        def organized_answer(items, answers)
          return answers.first.answer if items.one?

          lines = [ "Here is what I found:", "" ]
          items.zip(answers).each_with_index do |(item, answer), index|
            lines << "#{index + 1}. #{capitalized_label(item['label'])} — #{answer.answer}"
          end
          lines.join("\n")
        end

        def capitalized_label(label)
          label.to_s.strip.sub(/\A\p{Ll}/) { |character| character.upcase }
        end

        def information_response(items, answers, body)
          manager = context.task_manager
          topic = information_topic(items, answers)
          outcome = knowledge_outcome(answers)
          failure_topics = unavailable_topics(items, answers)
          payload = manager.update_information_task(
            intent: "hotel_information",
            topic: topic,
            question: context.message,
            outcome: outcome,
            failure_topics: failure_topics
          )
          manager = State::ConversationTaskManager.new(slots_payload: payload)
          failure_count = manager.information_task["consecutive_failure_count"].to_i
          decision = Escalation::Policy.new(
            hotel: hotel,
            conversation: context.conversation,
            trigger: "no_answer",
            failure_count: failure_count
          ).call

          if decision.handoff?
            rendered = [ body, decision.message ].compact_blank.join("\n\n")
            return Orchestration::Core::DomainResponse.new(
              slots_payload: manager.clear_optional_sales_offer,
              next_action: Orchestration::Sales::NextAction.new("offer_front_desk"),
              needs_human_support: true,
              extra_context: information_context(
                rendered,
                outcome: outcome,
                failure_count: failure_count,
                failure_topics: failure_topics,
                decision: decision
              )
            )
          end

          return failed_information_response(manager, body, outcome, failure_count, failure_topics) unless outcome == "answered"

          candidate_action = Orchestration::Sales::NextActionPolicy.new(
            intent: "hotel_information",
            topic: topic,
            outcome: "answered",
            booking_task: manager.booking_task,
            resumable_booking: false,
            suppress_offer: false
          ).call
          selected_action = Orchestration::Sales::NextActionPolicy.new(
            intent: "hotel_information",
            topic: topic,
            outcome: "answered",
            booking_task: manager.booking_task,
            resumable_booking: false,
            suppress_offer: manager.sales_offer_suppressed? || manager.sales_task["information_offer_shown"] == true
          ).call
          rendered = Orchestration::Sales::NextActionRenderer.new(
            answer: body,
            next_action: selected_action,
            intent: "hotel_information",
            acknowledge_refusal: manager.sales_refusal_acknowledgment_pending?,
            copy_index: manager.sales_task["optional_copy_index"],
            closing_copy_index: manager.sales_task["closing_copy_index"],
            natural_closer: natural_closer?(selected_action)
          ).call
          payload = if manager.sales_offer_suppressed? && candidate_action.optional?
            manager.consume_sales_offer_suppression
          elsif selected_action.optional?
            manager.record_optional_sales_offer(selected_action.kind)
          else
            manager.clear_optional_sales_offer
          end
          if natural_closer?(selected_action)
            payload = State::ConversationTaskManager.new(slots_payload: payload).record_information_closer
          end

          Orchestration::Core::DomainResponse.new(
            slots_payload: payload,
            next_action: selected_action,
            extra_context: information_context(
              rendered,
              outcome: outcome,
              failure_count: failure_count,
              failure_topics: failure_topics
            )
          )
        end

        def failed_information_response(manager, body, outcome, failure_count, failure_topics)
          retrying = hotel.guest_contact&.escalates_on?("no_answer") && outcome.in?(%w[partial unavailable])
          action = if outcome == "unavailable" && !retrying
            Orchestration::Sales::NextAction.new("offer_front_desk")
          else
            Orchestration::Sales::NextAction.none
          end
          rendered = if action.kind == "offer_front_desk"
            Orchestration::Sales::NextActionRenderer.new(
              answer: body,
              next_action: action,
              intent: "hotel_information",
              missing_topic: failure_topics.first
            ).call
          else
            body
          end

          Orchestration::Core::DomainResponse.new(
            slots_payload: manager.clear_optional_sales_offer,
            next_action: action,
            extra_context: information_context(
              rendered,
              outcome: outcome,
              failure_count: failure_count,
              failure_topics: failure_topics
            )
          )
        end

        def knowledge_outcome(answers)
          return "clarification" if answers.any? { |answer| answer.reply.shape == "clarification" }

          successful = answers.count { |answer| answer.reply.success }
          return "answered" if successful == answers.length
          return "unavailable" if successful.zero?

          "partial"
        end

        def unavailable_topics(items, answers)
          items.zip(answers).filter_map do |item, answer|
            next if answer.reply.success

            answer.reply.missing_topic.presence || item["label"].to_s
          end.uniq
        end

        def information_context(message, outcome:, failure_count:, failure_topics:, decision: nil)
          {
            message: message,
            knowledge_outcome: outcome,
            failure_count: failure_count,
            failure_topics: failure_topics,
            escalation_trigger: decision&.trigger,
            human_requested: decision&.handoff? || false
          }
        end

        def merge_information_result(booking_result, information_result)
          merged_slots = booking_result.slots_payload.merge(
            "information_task" => information_result.slots_payload["information_task"]
          )
          booking_result.with(
            slots_payload: merged_slots,
            needs_human_support: booking_result.needs_human_support || information_result.needs_human_support,
            extra_context: booking_result.extra_context.merge(information_result.extra_context.except(:message))
          )
        end

        def record_knowledge_diagnostics(items, answers, domain_result)
          items.zip(answers).each do |item, resolution|
            interpretation = interpretation_for(item)
            diagnostic_result = resolution.tool_result[:result]
              .merge(resolution.reply.to_h)
              .merge(
                "answer" => resolution.answer,
                "aggregate_outcome" => domain_result.extra_context[:knowledge_outcome],
                "escalation_attempt" => domain_result.extra_context[:failure_count],
                "escalation_trigger" => domain_result.extra_context[:escalation_trigger],
                "human_requested" => domain_result.extra_context[:human_requested]
              )
            Orchestration::HotelKnowledge::DiagnosticRecorder.new(
              hotel: hotel,
              message: item["evidence"],
              interpretation: interpretation,
              conversation_state: context.conversation_state,
              result: diagnostic_result
            ).call
          end
        end

        def information_topic(items, answers)
          item = items.one? ? items.first : nil
          answer = answers.one? ? answers.first : nil
          if item&.dig("kind") == "hotel_information" &&
              (item["scope"] == "broad" || answer&.reply&.shape == "list")
            return "hotel_overview"
          end

          "hotel_questions"
        end

        def natural_closer?(action)
          action.kind.in?(%w[none offer_booking_help])
        end

        def booking_response(commercial)
          intent = commercial["intent"].presence || "none"
          return unless intent != "none" || context.pending_question.present?
          return confirmation_reask if context.pending_question == "confirm_selection"

          advance_booking(commercial)
          clear_interruption_reask(recorder.outcome.domain_result)
        end

        def clear_interruption_reask(result)
          task = result.slots_payload["booking_task"]
          return result unless task.is_a?(Hash)

          result.with(
            slots_payload: result.slots_payload.merge("booking_task" => task.merge("reask_count" => 0)),
            extra_context: result.extra_context.except(:retry),
            needs_human_support: false
          )
        end

        def confirmation_reask
          manager = context.task_manager
          selected = manager.booking_branch["confirmation_candidate"] || manager.booking_branch["selected_option"]

          Orchestration::Core::DomainResponse.booking(
            slots_payload: manager.payload,
            reply_type: :ask_confirmation,
            pending_question: "confirm_selection",
            extra_context: { branch: manager.booking_branch, selected_option: selected }
          )
        end

        def advance_booking(commercial)
          AdvanceBookingFunction.new(context: context, recorder: recorder).execute(
            slots: commercial["slots"] || {},
            signals: commercial["signals"] || {},
            evidence: commercial["evidence"] || {}
          )
        end

        def booking_domain_response?(result)
          result.active_flow == "booking_search"
        end

        def append_booking_response(body, domain_result)
          booking_message = Agents::MessengerAgent.new(
            hotel: hotel,
            context: { reply_type: domain_result.reply_type, opening_reply: false }.merge(domain_result.extra_context)
          ).call.fetch("reply_message")
          "#{body}\n\n#{booking_message}"
        end
      end
    end
  end
end
