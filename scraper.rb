require 'scraperwiki'
require 'mechanize'

agent = Mechanize.new

{
  experience: "http://vvm-auto.ru/opyt-ekspluatatsii",
  articles: "http://vvm-auto.ru/publikatsii",
  tests: "http://vvm-auto.ru/test-obzor"
}.each do |type, base_url|
  p "[debug] Load #{type} from #{base_url}"
  page = agent.get(base_url)
  annotations = page.search('#content [itemprop="blogPost"]')
  annotations.each do |annotation|
    url = annotation.search('a')[0].href
    title = annotation.search('a')[0].text
    annotation_text = annotation.search('p')[0].text
    annotation_image = annotation.search('[itemprop="thumbnailUrl"]')[0].src
    data = {
      title: title,
      annotation_text: annotation_text,
      annotation_image: annotation_image
    }
    puts parse_page(url, data)
  end
  
end



def parse_page(url, data={})
  data.merge!({
    id: 1,
    type: 'experience',
    title: 'Title',
    annotation_image: 'Annotation image',
    annotation_text: 'Annotation',
    article: 'Full text',
    url: url
  }).to_s
end
