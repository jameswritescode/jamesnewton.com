# frozen_string_literal: true

module ApplicationHelper
  def javascript_pack_tag(app)
    return javascript_include_tag(app, defer: true) unless Rails.env.development?

    base = 'http://localhost:3035'
    json = JSON.parse(URI.parse("#{base}/assets-manifest.json").open.read)

    scripts = json['entrypoints'][app]['assets']['js'].map do |asset|
      tag.script(src: "#{base}/#{asset}")
    end

    safe_join(scripts)
  rescue Errno::ECONNREFUSED
    'not running yarn server'
  end
end
