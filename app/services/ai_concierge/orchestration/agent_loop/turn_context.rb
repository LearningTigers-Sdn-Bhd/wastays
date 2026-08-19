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
        def initialize(hotel:, prospect:, phone:, conversation_state:, message:)
          @hotel = hotel
          @prospect = prospect
          @phone = phone
          @conversation_state = conversation_state
          @message = message.to_s
        end

        attr_reader :hotel, :prospect, :phone, :conversation_state, :message

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
        def resumable_booking?
          task = booking_task
          return false if task["status"] == "expired" || suspended_booking_expired?

          task["status"] == "suspended" || task["suspended"] == true
        end

        def room_type_names
          @room_type_names ||= hotel.room_types.pluck(:name)
        end

        private

        def suspended_booking_expired?
          expires_at = Time.zone.parse(booking_task["expires_at"].to_s)
          expires_at.present? && expires_at <= Time.current
        rescue ArgumentError
          false
        end
      end
    end
  end
end
