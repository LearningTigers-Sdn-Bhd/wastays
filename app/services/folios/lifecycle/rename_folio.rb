# frozen_string_literal: true


module Folios
  module Lifecycle
    class RenameFolio
      include Authorizable

      PERMISSION = "manage_folio_windows"

      def self.call(folio:, user:, name:, reason: nil)
        new(folio: folio, user: user, name: name, reason: reason).call
      end

      def initialize(folio:, user:, name:, reason: nil)
        @folio = folio
        @booking = folio.booking
        @hotel = folio.hotel
        @user = user
        @name = name.to_s.strip
        @reason = reason.to_s.strip.presence
      end

      def call
        return failure("You do not have permission to manage folio windows.") unless permitted?
        return failure("Folio name can't be blank.") if @name.blank?
        return failure("Closed or voided folios cannot be renamed.") unless @folio.open?

        old_name = @folio.name
        @folio.with_lock do
          @folio.update!(name: @name)
          FolioOperationLog.create!(
            hotel: @hotel,
            booking: @booking,
            actor: @user,
            operation_type: "rename_folio",
            source_folio: @folio,
            target_folio: @folio,
            reason: @reason,
            currency: @folio.currency,
            metadata: { old_name: old_name, new_name: @folio.name }
          )
        end

        success(@folio)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        failure(e.message)
      end

      private

      def permitted?
        actor_permits?(@user, PERMISSION, hotel: @hotel)
      end

      def success(folio)
        Folios::Lifecycle::Result.success(folio: folio)
      end

      def failure(error)
        Folios::Lifecycle::Result.failure(error, folio: @folio)
      end
    end
  end
end
