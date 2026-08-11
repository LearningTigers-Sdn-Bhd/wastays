# frozen_string_literal: true

module HotelPortal
  module RoomGroups
    class Assign
      Result = Data.define(:room_group, :form) do
        def success? = room_group.present? && form.errors.empty?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, form:)
        @hotel = hotel
        @form = form
      end

      def call
        return Result.new(room_group: nil, form: form) unless form.valid?

        submitted_room_ids = Array(form.room_type_ids).compact_blank.map(&:to_s).uniq
        room_ids = submitted_room_ids.filter_map { |id| Integer(id, exception: false) }.uniq
        rooms = hotel.room_types.where(id: room_ids)

        if room_ids.size != submitted_room_ids.size || rooms.count != room_ids.size
          form.errors.add(:room_type_ids, "include one or more categories that are not available for this property.")
        end
        group = existing_group unless creating_group?
        form.errors.add(:room_group_id, "is not available for this property.") if !creating_group? && !group
        return Result.new(room_group: nil, form: form) if form.errors.any?

        ActiveRecord::Base.transaction do
          group ||= hotel.room_groups.create!(name: form.new_group_name)
          rooms.update_all(room_group_id: group.id, updated_at: Time.current)
        end
        Result.new(room_group: group, form: form)
      rescue ActiveRecord::RecordInvalid => error
        error.record.errors.full_messages.each { |message| form.errors.add(:new_group_name, message) }
        Result.new(room_group: nil, form: form)
      end

      private

      attr_reader :hotel, :form

      def creating_group? = form.room_group_id.to_s == "new"

      def existing_group
        hotel.room_groups.find_by(id: Integer(form.room_group_id, exception: false))
      end
    end
  end
end
