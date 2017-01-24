require 'scraperwiki'
require 'mechanize'
require 'nokogiri'
require 'reverse_markdown'

$agent = Mechanize.new
$site_url = "http://vvm-auto.ru"
$image_scraped = nil


def parse_pages(url, data={})
  return if url.nil?
  p "Parsing #{data[:type]} from #{url}"
  page = $agent.get(url)
  next_page_link = page.search('span.icon-next').length ? page.search('span.icon-next').first.parent.attribute('href').value : nil
  parse_page(data)
  p next_page_link
  unless true || next_page_link.nil?
    p "[debug] Go to next page #{next_page_link}"
    parse_pages($agent.resolve(next_page_link), data) 
  end
end

def parse_page(data={})
  page = $agent.page
  posts = page.search('#content [itemprop="blogPost"]')
  posts.each do |post|
    link_to_post = post.search('a').first
    url = $agent.resolve(link_to_post.attribute('href'))
    id = /\/(\d+)-/.match(url.to_s)[1].to_i

    begin
      article = ScraperWiki.select('* FROM data WHERE id = ? LIMIT 1', [id]).first
      next unless article.nil?
    rescue => error
      p "Database error: #{error.to_s}"
    end

    title = post.search('a').first.child.content.strip
    annotation_text = post.search('p').first.nil? ? nil : post.search('p').first.child.content
    annotation_image = post.search('[itemprop="thumbnailUrl"]').first.nil? ? nil : post.search('[itemprop="thumbnailUrl"]').attribute('src').value

    if annotation_image && !$image_scraped
      $image_scraped = scrape_image($agent.resolve(annotation_image))
      p $image_scraped
    end

    data.merge!({
      id: id,
      title: title,
      annotation_text: ReverseMarkdown.convert(annotation_text),
      annotation_image: "#{$site_url}#{annotation_image}",
      url: url.to_s
    })
    $agent.get(url)
    parse_article(data)
    ScraperWiki.save_sqlite([:id], data)
    p "[debug] Article with id = #{data[:id]} was parsed, full link: #{url}"
    sleep 5
  end
end

def parse_article(data={})
  #agent = Mechanize.new
  page = $agent.page #$agent.get(url)

  content = page.search('[itemprop="articleBody"]').first
  content.search('div.custom').each { |d| d.remove }
  content.search('img').each do |i|
    i.attribute('src').value = $agent.resolve(i.attribute('src').value).to_s
  end

  # content.each do |n|
  #   n.remove if n.empty?
  # end

  data.merge!({
    content: ReverseMarkdown.convert(content.to_html(options: Nokogiri::XML::Node::SaveOptions.new.no_empty_tags))
  })
end

def scrape_image(url)
  return nil unless url
  image = $agent.get_file(url)
  p "[debug] image #{url} fetched, size is: #{image.length}"
  image ? "sqlite://data.db/images/1" : nil
end


{
  experience: "opyt-ekspluatatsii",
  articles: "publikatsii",
  tests: "test-obzor"
}.each do |type, url|
  url = $site_url + "/" + url
  p "[debug] Load #{type} from #{url}"
  parse_pages(url, type: type.to_s)
end
