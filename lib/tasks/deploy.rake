# frozen_string_literal: true

namespace :deploy do
  task post: :environment do
    %w[db:prepare sitemap:refresh:no_ping].each do |task|
      Rake::Task[task].invoke
    end
  end
end
