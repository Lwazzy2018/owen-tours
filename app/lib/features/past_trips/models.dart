import '../../core/api/api_client.dart';

class PastTripSummary {
  PastTripSummary.fromJson(Json j)
      : id = j['id'] as String,
        tripId = j['tripId'] as String?,
        title = j['title'] as String,
        destination = j['destination'] as String,
        travelledOn = j['travelledOn'] as String,
        travellerCount = asIntOrNull(j['travellerCount']),
        coverUrl = j['coverUrl'] as String?,
        isFeatured = j['isFeatured'] == true,
        isPublished = j['isPublished'] == true,
        mediaCount = asInt(j['mediaCount']);
  final String id, title, destination, travelledOn;
  final String? tripId, coverUrl;
  final int? travellerCount;
  final bool isFeatured, isPublished;
  final int mediaCount;
}

class PastTripMedia {
  PastTripMedia.fromJson(Json j)
      : id = j['id'] as String,
        mediaType = j['mediaType'] as String,
        url = j['url'] as String,
        thumbnailUrl = j['thumbnailUrl'] as String?,
        caption = j['caption'] as String?,
        sortOrder = asInt(j['sortOrder']);
  final String id, mediaType, url;
  final String? thumbnailUrl, caption;
  final int sortOrder;
  bool get isVideo => mediaType == 'video';
}

class Testimonial {
  Testimonial.fromJson(Json j)
      : id = j['id'] as String,
        customerName = j['customerName'] as String,
        quote = j['quote'] as String,
        rating = asIntOrNull(j['rating']),
        photoUrl = j['photoUrl'] as String?,
        isPublished = j['isPublished'] == true;
  final String id, customerName, quote;
  final int? rating;
  final String? photoUrl;
  final bool isPublished;
}

class PastTripDetail {
  PastTripDetail.fromJson(Json j)
      : id = j['id'] as String,
        tripId = j['tripId'] as String?,
        title = j['title'] as String,
        destination = j['destination'] as String,
        travelledOn = j['travelledOn'] as String,
        travellerCount = asIntOrNull(j['travellerCount']),
        story = j['story'] as String?,
        coverUrl = j['coverUrl'] as String?,
        isFeatured = j['isFeatured'] == true,
        isPublished = j['isPublished'] == true,
        sortOrder = asInt(j['sortOrder']),
        media = asList(j['media'], PastTripMedia.fromJson),
        testimonials = asList(j['testimonials'], Testimonial.fromJson),
        hasUpcomingTrip = j['hasUpcomingTrip'] == true;
  final String id, title, destination, travelledOn;
  final String? tripId, story, coverUrl;
  final int? travellerCount;
  final bool isFeatured, isPublished, hasUpcomingTrip;
  final int sortOrder;
  final List<PastTripMedia> media;
  final List<Testimonial> testimonials;
}
