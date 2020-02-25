unless @sessions.nil?
  json.array!(@sessions) do |session|

    json.id session.id
    json.name ""
    json.email ""
    json.created_time_stamp format_date(session.created_at)
    get_pages_viewed = session.get_pages_viewed(@parent)
    json.percent_viewed number_to_percentage(get_pages_viewed, precision: 0)
    json.percent_viewed_tooltip session.get_pages_viewed(@parent,'number')

    get_secs_viewed = session.get_secs_viewed(@parent)
    json.min_viewed format_time(get_secs_viewed)
    json.sec_viewed get_secs_viewed

    get_total_secs_viewed = session.get_secs_viewed(@parent)
    json.total_min_viewed format_time(get_total_secs_viewed)
    json.total_secs_viewed get_total_secs_viewed

    json.engagement number_to_percentage(session.get_engagement(@parent), precision: 2)

    get_page_secs_viewed = session.get_page_secs_viewed
    json.page_min_viewed format_time(get_page_secs_viewed)
    json.page_sec_viewed get_page_secs_viewed

    json.most_viewed_pages session.get_popular_pages
    json.page_tags @parent[:page_tags]

    get_pages_by_most_time_spent = session.get_pages_by_most_time_spent
    get_pages_by_most_time_spent[:time_spent] = format_time(get_pages_by_most_time_spent[:time_spent])
    json.pages_by_time_spent get_pages_by_most_time_spent
    json.popular_exit_pages session.get_exit_page(@parent)

    json.time_per_page (session.get_secs_viewed_by_page) do |time_on_page|
      json.page time_on_page[:page]
      json.min_on_page format_time_in_mins(time_on_page[:secs])
      json.secs_on_page time_on_page[:secs]
      json.total_min_on_page format_time_in_mins(time_on_page[:total_secs])
      json.total_secs_on_page time_on_page[:total_secs]
      json.views time_on_page[:views]
    end

    json.element_clicks session.get_elements_click

    json.sessions (@sessions.date_desc) do |_session|
      json.partial! 'statistics/partials/sessions/session', session: _session
    end
  end
else
  json.array!(@receivers) do |receiver|
    json.id receiver.id
    json.name_reversed receiver.name_reversed
    json.name receiver.name
    json.email receiver.email
    json.created_time_stamp format_date(receiver.created_at)
    get_pages_viewed = receiver.get_pages_viewed(@parent)
    json.percent_viewed number_to_percentage(get_pages_viewed, precision: 0)
    json.percent_viewed_tooltip receiver.get_pages_viewed(@parent,'number')

    get_secs_viewed = receiver.get_secs_viewed(@parent)
    json.min_viewed format_time(get_secs_viewed)
    json.sec_viewed get_secs_viewed

    get_total_secs_viewed = receiver.get_secs_viewed(@parent, 'total')
    json.total_min_viewed format_time(get_total_secs_viewed)
    json.total_secs_viewed get_total_secs_viewed

    json.engagement number_to_percentage(receiver.get_engagement(@parent), precision: 2)

    get_page_secs_viewed = receiver.get_page_secs_viewed(@parent)
    json.page_min_viewed format_time(get_page_secs_viewed)
    json.page_sec_viewed get_page_secs_viewed

    json.most_viewed_pages receiver.get_popular_pages(@parent)
    json.page_tags @parent[:page_tags]

    get_pages_by_most_time_spent = receiver.get_pages_by_most_time_spent(@parent)
    get_pages_by_most_time_spent[:time_spent] = format_time(get_pages_by_most_time_spent[:time_spent])
    json.pages_by_time_spent get_pages_by_most_time_spent
    json.popular_exit_pages receiver.get_exit_pages(@parent)

    json.time_per_page (receiver.get_secs_viewed_by_page(@parent)) do |time_on_page|
      json.page time_on_page[:page]
      json.min_on_page format_time_in_mins(time_on_page[:secs])
      json.secs_on_page time_on_page[:secs]
      json.total_min_on_page format_time_in_mins(time_on_page[:total_secs])
      json.total_secs_on_page time_on_page[:total_secs]
      json.views time_on_page[:views]
    end

    json.element_clicks receiver.get_elements_click(@parent)
    sessions = if @parent[:type] == 'tracking_link'
                 receiver.sessions.viewed.by_tl(@parent[:id])
               elsif @parent[:type] == 'doc'
                 receiver.sessions.viewed.by_doc(@parent[:id])
               end
    json.sessions (sessions.date_desc) do |session|
      json.partial! 'statistics/partials/sessions/session', session: session
    end
  end
end