# frozen_string_literal: true

module Admin
  module Hotels
    # Imports a property's unarrived reservations from an eZee export.
    #
    # Three steps. The preview exists because bookings are created through
    # Bookings::CreateManualBooking, which validates availability -- so a row can
    # fail on inventory the property has not set up, and finding that out 900
    # bookings into a commit is useless.
    #
    # The commit then runs in the background, because a thousand reservations,
    # each building a financial snapshot and a folio, is not a request. The
    # operator watches a ReservationImport row rather than a spinner.
    class ReservationImportsController < Admin::BaseController
      before_action :set_hotel
      before_action :set_import, only: %i[show commit]

      def new
      end

      def show
      end

      def create
        file = params[:file]
        return redirect_back_with("Choose a file to import.") if file.blank?

        @import = @hotel.reservation_imports.create!(user: current_user, status: "draft")
        @import.file.attach(io: file.tempfile, filename: file.original_filename)

        @parsed = parse(@import)
        unless @parsed.success?
          @import.destroy
          return redirect_back_with(@parsed.error)
        end

        @plan = Ezee::ImportPlan.call(hotel: @hotel, rows: @parsed.rows)
        @import.update!(total_rows: @plan.importable.size)
        render :preview
      end

      def commit
        return redirect_to_progress unless @import.status == "draft"

        @import.update!(status: "queued", step: "Waiting to start")
        Ezee::RunReservationImportJob.perform_later(@import.id)
        redirect_to_progress
      end

      private

      def set_hotel
        @hotel = Hotel.locate!(params[:hotel_id])
      end

      def set_import
        @import = @hotel.reservation_imports.find(params[:id])
      end

      def redirect_to_progress
        redirect_to admin_hotel_reservation_import_path(@hotel, @import)
      end

      # Roo needs a path with a meaningful extension, and the attachment is only
      # a key in storage, so it is written out under its original name.
      def parse(import)
        blob = import.file.blob
        Tempfile.create([ "ezee", File.extname(blob.filename.to_s) ], binmode: true) do |tempfile|
          tempfile.write(blob.download)
          tempfile.flush
          Ezee::ReservationListParser.call(path: tempfile.path, filename: blob.filename.to_s)
        end
      end

      def redirect_back_with(message)
        redirect_to new_admin_hotel_reservation_import_path(@hotel), alert: message
      end
    end
  end
end
