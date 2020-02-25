json.array!(@sessions) do |session|

  json.partial! 'statistics/partials/sessions/session', session: session

  get_page_secs_viewed = session.get_page_secs_viewed
  json.page_min_viewed format_time(get_page_secs_viewed)
  json.page_sec_viewed get_page_secs_viewed

  json.time_per_page (session.get_secs_viewed_by_page) do |time_on_page|
    json.page time_on_page[:page]
    json.min_on_page format_time(time_on_page[:secs])
    json.secs_on_page time_on_page[:secs]
    json.total_min_on_page format_time(time_on_page[:total_secs])
    json.total_secs_on_page time_on_page[:total_secs]
    json.views time_on_page[:views]
  end
  json.element_clicks session.get_elements_click
  json.receiver do
    unless session.receiver.nil?
      json.id session.receiver.id
      json.name session.receiver.name.blank? ? session.receiver.email : session.receiver.name
      json.email session.receiver.email
    end
  end
end
