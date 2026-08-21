# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # Everything a tool needs about the turn it is running in, and everything
      # the loop knows that the model is not asked to decide.
      #
      # The distinction matters: whether a booking is suspended, whether an
      # information question is interrupting one, which question is currently
      # open -- these are facts in Postgres. A model asked to restate them can
      # get them wrong, so it is not asked.
      class TurnContext
        # How much of the thread the model is shown. Three exchanges is enough
        # for "the cheaper one" and "make it 3 nights instead" to mean
        # something, and short enough that the cost of a turn does not grow
        # with the length of the conversation.
        HISTORY_LIMIT = 6

        # A catalogue reply is the longest thing in any thread and the least
        # worth carrying in full: which row the guest meant is answered from
        # Postgres by Matching::OptionReference, not by re-reading the list.
        MAX_HISTORY_BODY = 500

        def initialize(hotel:, prospect:, phone:, conversation_state:, message:,
                       thread_language: nil, conversation: nil)
          @hotel = hotel
          @prospect = prospect
          @phone = phone
          @conversation_state = conversation_state
          @message = message.to_s
          @thread_language = thread_language.presence
          @conversation = conversation
        end

        attr_reader :hotel, :prospect, :phone, :conversation_state, :message, :thread_language,
                    :conversation

        # The last few turns, as the model should read them.
        #
        # Reading material, not truth. Everything the system decides -- which
        # question is open, which branch is live, which option was picked --
        # still comes from the columns above, and a model that reads this
        # differently is still overruled by them. It is here so that a guest
        # who says "the cheaper one" is saying something, rather than something
        # a new deterministic reader has to be written for.
        #
        # Empty when there is no conversation, which is every spec that builds
        # a context without one and the only reason the argument is optional.
        def recent_messages
          @recent_messages ||= build_recent_messages
        end

        def task_manager
          State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
        end

        def booking_task = task_manager.booking_task
        def booking_branch = task_manager.booking_branch
        def pending_question = task_manager.booking_pending_question || conversation_state.pending_question

        # Whether answering a question now means putting a booking down rather
        # than dropping it. Lifted from TransitionPolicy#info_interruption_active?
        # unchanged -- the rule is about state, so it survives the rewrite.
        def info_interruption_active?
          branch = booking_branch
          branch.is_a?(Hash) && branch.present? && (
            branch["target_month"].present? || branch["check_in"].present? || pending_question.present?
          )
        end

        # A booking that was put down and can still be picked up. Also from
        # TransitionPolicy, and also a fact rather than a judgement: what the
        # model contributes is whether the guest is talking about booking at
        # all, which is the part a model is actually good at.
        #
        # The rule and its expiry live on the task manager, which owns the
        # column -- this was a second copy of both, down to its own parser.
        def resumable_booking? = task_manager.suspended_booking_resumable?

        def room_type_names
          @room_type_names ||= hotel.room_types.pluck(:name)
        end

        # Which languages this hotel actually wrote its knowledge base in.
        # Keyword search matches words, so a question has to be looked up in the
        # language the answer was filed under, and only the hotel knows what
        # that is -- it picks one per document on upload.
        def knowledge_languages
          @knowledge_languages ||= hotel.knowledge_documents.distinct.pluck(:language).compact_blank.sort
        end

        private

        def build_recent_messages
          return [] if conversation.blank?

          rows = conversation.messages
            .where.not(direction: "system")
            .where.not(body: [ nil, "" ])
            .reorder(sent_at: :desc, created_at: :desc)
            .limit(HISTORY_LIMIT + 1)
            .to_a
            .reverse

          drop_current_message!(rows)

          rows.last(HISTORY_LIMIT).map do |row|
            {
              role: row.from_guest? ? :user : :assistant,
              content: row.body.to_s.strip[0, MAX_HISTORY_BODY]
            }
          end
        end

        # The message being answered is already filed by the time the loop runs
        # -- PostWebMessage on the web, SessionLoader on WhatsApp -- and
        # RubyLLM::Chat#ask adds it again as the user turn. Without this the
        # model is handed the same message twice, and the second copy reads as
        # the guest repeating themselves.
        def drop_current_message!(rows)
          last = rows.last
          rows.pop if last&.from_guest? && last.body.to_s.strip == message.strip
        end
      end
    end
  end
end
