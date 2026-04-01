class HelpCenterController < ApplicationController
  GUIDE_BASE_DIRECTORY = Rails.root.join("markdowns", "guides")
  AUDIENCE_SECTION_STYLES = {
    "hotel_admin" => {
      accent_bar_class: "bg-brand-secondary",
      badge_class: "bg-orange-50 text-brand-secondary",
      title: "Hotel Operators",
      subtitle: "Management & Front Desk",
      hover_class: "group-hover/item:text-brand-secondary"
    },
    "superadmin" => {
      accent_bar_class: "bg-brand-primary",
      badge_class: "bg-red-50 text-brand-primary",
      title: "Platform Control",
      subtitle: "Internal Operations",
      hover_class: "group-hover/item:text-brand-primary"
    }
  }.freeze
  GUIDE_NAME_PATTERN = /\A[a-z0-9_-]+\z/

  before_action :authenticate_user!
  helper_method :list_guides

  def index
    @guide_sections = visible_audiences.map do |audience|
      guides = list_guides(audience)

      next if guides.empty?

      guide_section(audience, guides)
    end.compact
  end

  def show
    @audience = params[:audience]
    @slug = params[:id]

    unless valid_guide_request?(@audience, @slug)
      redirect_to help_center_path, alert: "Guide not found"
      return
    end

    # Security check: only superadmins can see superadmin guides
    if internal_audience?(@audience) && !current_user.superadmin?
      redirect_to help_center_path, alert: "Not authorized"
      return
    end

    guide = list_guides(@audience, include_content: true).find { |entry| entry[:slug] == @slug }

    unless guide
      redirect_to help_center_path, alert: "Guide not found"
      return
    end

    @html_content = guide[:html_content]
    @title = guide[:title]
  end

  private

  def valid_guide_request?(audience, slug)
    visible_audiences.include?(audience) && slug.match?(GUIDE_NAME_PATTERN)
  end

  def list_guides(audience, include_content: false)
    dir = audience_directory(audience)
    return [] unless dir
    return [] unless Dir.exist?(dir)

    dir.children.select { |path| path.extname == ".md" }.sort.map do |path|
      slug = path.basename(".md").to_s
      guide = {
        slug: slug,
        title: slug.titleize,
        audience: audience
      }

      guide[:html_content] = Commonmarker.to_html(path.read) if include_content
      guide
    end
  end

  def visible_audiences
    available_audiences.select do |audience|
      current_user.superadmin? || !internal_audience?(audience)
    end
  end

  def available_audiences
    return [] unless Dir.exist?(GUIDE_BASE_DIRECTORY)

    GUIDE_BASE_DIRECTORY.children.select(&:directory?).filter_map do |path|
      audience = path.basename.to_s
      audience if audience.match?(GUIDE_NAME_PATTERN)
    end.sort
  end

  def audience_directory(audience)
    return unless audience.match?(GUIDE_NAME_PATTERN)

    directory = GUIDE_BASE_DIRECTORY.join(audience)
    directory if directory.directory?
  end

  def internal_audience?(audience)
    audience == "superadmin"
  end

  def guide_section(audience, guides)
    styles = AUDIENCE_SECTION_STYLES.fetch(audience, default_section_styles(audience))

    {
      audience: audience,
      guides: guides,
      accent_bar_class: styles[:accent_bar_class],
      badge_class: styles[:badge_class],
      title: styles[:title],
      subtitle: styles[:subtitle],
      hover_class: styles[:hover_class]
    }
  end

  def default_section_styles(audience)
    {
      accent_bar_class: "bg-neutral-border",
      badge_class: "bg-neutral-bg text-neutral-text-primary",
      title: audience.titleize,
      subtitle: "Knowledge Base",
      hover_class: "group-hover/item:text-neutral-text-primary"
    }
  end
end
