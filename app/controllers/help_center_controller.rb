class HelpCenterController < ApplicationController
  before_action :authenticate_user!
  helper_method :list_guides

  def index
    @hotel_guides = list_guides('hotel_admin')
    @superadmin_guides = current_user.superadmin? ? list_guides('superadmin') : []
  end

  def show
    @audience = params[:audience]
    @slug = params[:id]

    # Security check: only superadmins can see superadmin guides
    if @audience == 'superadmin' && !current_user.superadmin?
      redirect_to help_center_path, alert: "Not authorized"
      return
    end

    file_path = Rails.root.join('markdowns', 'guides', @audience, "#{@slug}.md")

    if File.exist?(file_path)
      content = File.read(file_path)
      # Using the Commonmarker module (v1.x uses Commonmarker.to_html)
      @html_content = Commonmarker.to_html(content)
      @title = @slug.titleize
    else
      redirect_to help_center_path, alert: "Guide not found"
    end
  end

  private

  def list_guides(audience)
    dir = Rails.root.join('markdowns', 'guides', audience)
    return [] unless Dir.exist?(dir)

    Dir.glob("#{dir}/*.md").map do |path|
      slug = File.basename(path, '.md')
      {
        slug: slug,
        title: slug.titleize,
        audience: audience
      }
    end
  end
end
