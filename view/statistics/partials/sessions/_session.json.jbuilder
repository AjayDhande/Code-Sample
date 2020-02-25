json.id session.id
json.ip session.ip
json.continent session.continent
json.country session.country
json.city session.city
json.subdivision session.subdivision
json.browser session.browser
json.terms_time session.terms_time
json.policy_time session.policy_time
json.os session.os
json.os_family session.os_family
json.device session.device
json.tracking_stats_link get_link_stats_url(session)
json.tracking_link_tooltip session.tracking_links.first.name
json.date format_date(session.created_at)

json.browser_info session.browser_info
json.ip_details session.ip_details

json.engagement number_to_percentage(session.get_engagement(@parent), precision: 0)

get_pages_viewed = session.get_pages_viewed(@parent)
json.percent_viewed number_to_percentage(get_pages_viewed, precision: 0)
json.percent_viewed_tooltip number_to_percentage(get_pages_viewed, precision: 2)

get_secs_viewed = session.get_secs_viewed
json.min_viewed format_time(get_secs_viewed)
json.sec_viewed get_secs_viewed

json.most_viewed_pages session.get_popular_pages
get_pages_by_most_time_spent = session.get_pages_by_most_time_spent
get_pages_by_most_time_spent[:time_spent] = format_time(get_pages_by_most_time_spent[:time_spent])
json.pages_by_time_spent get_pages_by_most_time_spent

json.popular_exit_pages session.get_exit_page(@parent)

json.page_tags @parent[:page_tags]

i = 0
json.pages(session.session_pages) do |page|
  json.page page.page
  # json.tags page.docs_file.page_tags(true)[page.page]
  json.seconds page.seconds_on_page
  json.min_viewed format_time(page.seconds_on_page)
  json.date format_date(page.created_at)
  json.viewed_at format_time_from_date(page.created_at)
  json.video_on_page page.doc.docs_elements.find_by(page: page.page, element_type: 5).nil? ? false : true  
  if(i == 0)
    json.landing_page page.tracking_link.landing_page
    i += 1
  end
  json.elements (page.session_page_clicks.multi_click) do |page_click|
    json.id page_click.docs_element_id
    json.name t("stats.js.messages.#{Docs::Element::TYPE_NAME[page_click.docs_element.element_type].downcase}")
    json.clicks page_click.clicks.to_s + ' ' + (page_click.clicks != 1 ? t('stats.js.messages.clicks') : t('stats.js.messages.click'))
  end
end