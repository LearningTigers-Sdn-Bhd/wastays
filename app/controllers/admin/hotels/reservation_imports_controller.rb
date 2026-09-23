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
    # The file is read once, at upload, into ReservationImportRow. The preview
    # then pages over those rows and the commit reads them, so a thousand-row
    # file costs one parse rather than one per page view.
    class ReservationImportsController < Admin::BaseController
      PER_PAGE = 50

      before_action :set_hotel
      before_action :set_import, only: %i[show rows commit]

      def new
      end

      # A draft has not been approved yet, so it shows the review; anything past
      # that shows progress. Both are GETs on the same record, which is also
      # what lets Turbo accept the upload -- a form response has to redirect.
      def show
        return render :progress unless @import.status == "draft"

        load_preview
        render :preview
      end

      # One page of the review table, fetched by the lazy frame at the bottom of
      # the page before it. Keeps a thousand-row file off the first response.
      def rows
        load_rows
        render partial: "admin/hotels/reservation_imports/rows_page",
               locals: { hotel: @hotel, import: @import, rows: @rows,
                         filter: @filter, q: @q, page: @page, more: @more }
      end

      def create
        file = params[:file]
        return redirect_back_with("Choose a file to import.") if file.blank? || !file.respond_to?(:tempfile)

        import = @hotel.reservation_imports.create!(user: current_user, status: "draft")
        import.file.attach(io: file.tempfile, filename: file.original_filename)

        result = Ezee::BuildImportRows.call(import: import)
        unless result.success?
          import.destroy
          return redirect_back_with(result.error)
        end

        redirect_to admin_hotel_reservation_import_path(@hotel, import)
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

      # Counts come from the database rather than from a re-resolved file, so
      # the summary costs a handful of grouped queries whatever the file size.
      def load_preview
        @counts = @import.rows.group(:status).count
        @total_rows = @import.rows.count
        @attention_count = @import.rows.needing_attention.count
        @group_count = @import.rows.importable.where.not(group_key: nil).distinct.count(:group_key)
        @total_value = @import.rows.importable.sum(:total_amount)
        @business_date = @hotel.current_business_date || @hotel.business_date_for
        load_agencies
        load_rows
      end

      # Agencies are grouped by their normalised name, so several spellings of
      # one agency count once. The name an account is created with is the
      # canonical spelling, not whichever row the database returned first.
      def load_agencies
        by_agency = @import.rows.importable.where.not(agency_name: nil)
                           .group(:agency_name).count
                           .group_by { |name, _count| Ezee::ImportPlan.normalize_agency(name) }
                           .transform_values(&:to_h)
        existing = @hotel.hotel_corporate_accounts.includes(:corporate_account).index_by do |link|
          Ezee::ImportPlan.normalize_agency(link.corporate_account&.name)
        end

        matched, unmatched = by_agency.partition { |key, _counts| existing.key?(key) }
        @matched_agencies = matched.map { |_key, counts| Ezee::ImportPlan.canonical_agency_name(counts) }
        @new_agencies = unmatched.map { |_key, counts| Ezee::ImportPlan.canonical_agency_name(counts) }

        @agency_collisions = by_agency.filter_map do |_key, counts|
          next if counts.size < 2

          Ezee::ImportPlan::AgencyCollision.new(
            spellings: counts.keys.sort, canonical: Ezee::ImportPlan.canonical_agency_name(counts)
          )
        end
      end

      def load_rows
        @q = params[:q].presence
        # A search should look across every status by default -- landing it on
        # "Needs attention" (today's default when the import has any) would
        # make a match outside that bucket look like the search found nothing.
        @filter = params[:filter].presence_in(%w[all attention importable imported past]) ||
          (@q.present? ? "all" : default_filter)
        @page = [ params[:page].to_i, 1 ].max
        scope = filtered_rows(@filter).search(@q).in_sheet_order
        @rows = scope.limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
        @more = @rows.size > PER_PAGE
        @rows = @rows.first(PER_PAGE)
      end

      # Land on the problems when there are any: the operator's job here is to
      # decide whether to commit, and that decision turns on what went wrong.
      def default_filter
        @import.rows.needing_attention.exists? ? "attention" : "all"
      end

      def filtered_rows(filter)
        case filter
        when "attention" then @import.rows.needing_attention
        when "all" then @import.rows
        else @import.rows.where(status: filter)
        end
      end

      def redirect_to_progress
        redirect_to admin_hotel_reservation_import_path(@hotel, @import)
      end

      def redirect_back_with(message)
        redirect_to new_admin_hotel_reservation_import_path(@hotel), alert: message
      end
    end
  end
end
