# frozen_string_literal: true

class TwitterService
  include ActionView::Helpers::DateHelper

  def content
    tweet['text']
  end

  def created
    ago = time_ago_in_words(DateTime.parse(tweet['created_at']))

    "#{ago} ago"
  end

  private

  def access_token
    credentials = Rails.application.credentials[:twitter]

    OAuth::AccessToken.from_hash(
      OAuth::Consumer.new(
        credentials[:api_key],
        credentials[:api_secret],
        scheme: :header,
        site: 'http://api.twitter.com',
      ),
      credentials.slice(:oauth_token, :oauth_token_secret),
    )
  end

  def tweet
    @tweet ||= JSON.parse(
      access_token.request(
        :get,
        'https://api.twitter.com/1.1/statuses/user_timeline/jameswritescode.json?count=1',
      ).body,
    ).first
  end
end
