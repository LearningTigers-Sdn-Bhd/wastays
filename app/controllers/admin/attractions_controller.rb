# frozen_string_literal: true

module Admin
  class AttractionsController < Admin::BaseController
    PAGE_SIZE = 25
    FILTER_STATUSES = %w[pending approved archived].freeze

    before_action :set_attraction, only: %i[edit update approve reject archive restore merge]
    before_action :load_review_context, only: %i[edit update reject merge]

    def index
      @active_status = normalized_status
      @status_counts = status_counts

      scope = Attraction.includes(:source_hotel, :hotels).order(created_at: :desc, id: :desc)
      scope = scope.where(status: @active_status) unless @active_status == "all"
      scope = apply_search(scope)
      @pagy, @attractions = pagy_offset(scope, limit: PAGE_SIZE)
    end

    def new
      @google_maps_url = params[:google_maps_url].to_s
    end

    def preview
      @google_maps_url = google_maps_url_param
      result = Attractions::GoogleMapsUrlParser.call(@google_maps_url)

      if result.success?
        @parsed = result.parsed
        @duplicate = Attractions::FindDuplicate.call(fingerprint: @parsed.fingerprint)
        render :new
      else
        @parser_error = result.error
        render :new, status: :unprocessable_content
      end
    end

    def create
      @google_maps_url = google_maps_url_param
      result = Attractions::GoogleMapsUrlParser.call(@google_maps_url)

      unless result.success?
        @parser_error = result.error
        return render :new, status: :unprocessable_content
      end

      @parsed = result.parsed
      @duplicate = Attractions::FindDuplicate.call(fingerprint: @parsed.fingerprint)
      @attraction = create_or_approve_attraction!
      complete_sheet(notice: "Attraction approved and added to the registry.")
    rescue ActiveRecord::RecordInvalid => error
      @attraction = error.record
      render :new, status: :unprocessable_content
    end

    def edit; end

    def update
      if @attraction.update(attraction_params)
        complete_sheet(notice: "Attraction updated.")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def approve
      @attraction.update!(
        status: :approved,
        reviewed_by: current_user,
        reviewed_at: Time.current,
        review_note: nil,
        archived_from_status: nil
      )
      complete_sheet(notice: "Attraction approved.")
    end

    def reject
      note = params.dig(:attraction, :review_note).to_s.strip
      if note.blank?
        @attraction.errors.add(:review_note, "is required when you reject an attraction")
        return render :edit, status: :unprocessable_content
      end

      @attraction.update!(
        status: :rejected,
        reviewed_by: current_user,
        reviewed_at: Time.current,
        review_note: note,
        archived_from_status: nil
      )
      complete_sheet(notice: "Attraction rejected.")
    end

    def archive
      unless @attraction.status_archived?
        @attraction.update!(
          archived_from_status: @attraction.status,
          status: :archived,
          reviewed_by: current_user,
          reviewed_at: Time.current
        )
      end
      complete_sheet(notice: "Attraction archived.")
    end

    def restore
      restored_status = @attraction.archived_from_status.presence_in(Attraction.statuses.keys - [ "archived" ]) || "approved"
      @attraction.update!(
        status: restored_status,
        archived_from_status: nil,
        reviewed_by: current_user,
        reviewed_at: Time.current
      )
      complete_sheet(notice: "Attraction restored.")
    end

    def merge
      target = Attraction.find(params.dig(:merge, :target_id) || params[:target_id])
      result = Attractions::Merge.call(source: @attraction, target: target, reviewer: current_user)

      if result.success?
        complete_sheet(notice: "Attractions merged. #{result.merged_links_count} hotel links moved.")
      else
        @attraction.errors.add(:base, result.error)
        render :edit, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotFound
      @attraction.errors.add(:base, "Select a valid target attraction.")
      render :edit, status: :unprocessable_content
    end

    private

    def set_attraction
      @attraction = Attraction.find(params[:id])
    end

    def normalized_status
      params[:status].presence_in(FILTER_STATUSES) || "all"
    end

    def status_counts
      counts = Attraction.group(:status).count
      {
        "all" => counts.values.sum,
        "pending" => counts.fetch("pending", 0),
        "approved" => counts.fetch("approved", 0),
        "archived" => counts.fetch("archived", 0)
      }
    end

    def apply_search(scope)
      query = params[:q].to_s.strip
      return scope if query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      scope.left_joins(:hotels, :source_hotel)
        .where(
          "attractions.name ILIKE :pattern OR attractions.city ILIKE :pattern OR " \
          "attractions.country ILIKE :pattern OR hotels.name ILIKE :pattern OR " \
          "source_hotels_attractions.name ILIKE :pattern OR " \
          "CAST(attractions.latitude AS TEXT) ILIKE :pattern OR " \
          "CAST(attractions.longitude AS TEXT) ILIKE :pattern",
          pattern:
        ).distinct
    end

    def load_review_context
      @possible_duplicates = possible_duplicates
      @merge_targets = @possible_duplicates.presence || Attraction.where(status: %i[pending approved]).where.not(id: @attraction.id).order(:name).limit(100)
    end

    def possible_duplicates
      scope = Attraction.where.not(id: @attraction.id).where.not(status: :archived)
      conditions = []
      values = {}

      if @attraction.normalized_name.present?
        conditions << "normalized_name = :normalized_name"
        values[:normalized_name] = @attraction.normalized_name
      end

      if @attraction.latitude.present? && @attraction.longitude.present?
        conditions << "(latitude BETWEEN :min_latitude AND :max_latitude AND longitude BETWEEN :min_longitude AND :max_longitude)"
        values.merge!(
          min_latitude: @attraction.latitude - 0.01,
          max_latitude: @attraction.latitude + 0.01,
          min_longitude: @attraction.longitude - 0.01,
          max_longitude: @attraction.longitude + 0.01
        )
      end

      return Attraction.none if conditions.empty?

      scope.where(conditions.join(" OR "), values).order(:name).limit(10)
    end

    def google_maps_url_param
      params.dig(:attraction, :google_maps_url).to_s.strip.presence || params[:google_maps_url].to_s.strip
    end

    def create_or_approve_attraction!
      attraction = @duplicate&.merged_into || @duplicate
      if attraction
        attraction.update!(
          status: :approved,
          reviewed_by: current_user,
          reviewed_at: Time.current,
          review_note: nil,
          archived_from_status: nil
        )
        return attraction
      end

      Attraction.create!(
        name: @parsed.name,
        normalized_name: @parsed.normalized_name,
        google_maps_url: @parsed.google_maps_url,
        latitude: @parsed.latitude,
        longitude: @parsed.longitude,
        coordinate_fingerprint: @parsed.fingerprint,
        status: :approved,
        submitted_by: current_user,
        reviewed_by: current_user,
        reviewed_at: Time.current
      )
    end

    def attraction_params
      params.require(:attraction).permit(:name, :shared_summary, :address, :city, :country)
    end

    def complete_sheet(notice:)
      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = notice
          render body: helpers.turbo_stream_action_tag(
            :complete_sheet,
            target: "admin_attraction_action_sheet",
            url: admin_attractions_path
          ), content_type: Mime[:turbo_stream]
        end
        format.html { redirect_to admin_attractions_path, notice:, status: :see_other }
      end
    end
  end
end
