import '../../core/api/api_client.dart';

class WhatsIncluded {
  WhatsIncluded.fromJson(Json j)
      : transportIncluded = j['transportIncluded'] == true,
        transportType = j['transportType'] as String?,
        transportNotes = j['transportNotes'] as String?,
        breakfast = j['breakfast'] == true,
        lunch = j['lunch'] == true,
        dinner = j['dinner'] == true,
        snacks = j['snacks'] == true,
        mealsNotes = j['mealsNotes'] as String?,
        mealsSummary = (j['mealsSummary'] ?? 'No meals included') as String,
        accommodationIncluded = j['accommodationIncluded'] == true,
        accommodationType = j['accommodationType'] as String?,
        accommodationNotes = j['accommodationNotes'] as String?,
        otherIncludes = asStrings(j['otherIncludes']),
        excludes = asStrings(j['excludes']);

  final bool transportIncluded;
  final String? transportType;
  final String? transportNotes;
  final bool breakfast, lunch, dinner, snacks;
  final String? mealsNotes;
  final String mealsSummary;
  final bool accommodationIncluded;
  final String? accommodationType;
  final String? accommodationNotes;
  final List<String> otherIncludes;
  final List<String> excludes;

  bool get anyMeals => breakfast || lunch || dinner || snacks;
}

class TripSummary {
  TripSummary.fromJson(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        destination = j['destination'] as String,
        destinationCountry = j['destinationCountry'] as String,
        isCrossBorder = j['isCrossBorder'] == true,
        category = j['category'] as String,
        audience = j['audience'] as String,
        tagline = j['tagline'] as String?,
        coverImageUrl = j['coverImageUrl'] as String?,
        fromPriceCents = asIntOrNull(j['fromPriceCents']),
        nextDepartureAt = asDate(j['nextDepartureAt']),
        seatsLeftNext = asIntOrNull(j['seatsLeftNext']),
        departsFrom = asStrings(j['departsFrom']),
        transportIncluded = j['transportIncluded'] == true,
        mealsSummary = (j['mealsSummary'] ?? '') as String,
        accommodationIncluded = j['accommodationIncluded'] == true,
        cancellationBadge = j['cancellationBadge'] as String?,
        specialBadge = j['specialBadge'] as String?,
        isPublished = j['isPublished'] == true;

  final String id, title, destination, destinationCountry, category, audience, mealsSummary;
  final bool isCrossBorder, transportIncluded, accommodationIncluded, isPublished;
  final String? tagline, coverImageUrl, cancellationBadge, specialBadge;
  final int? fromPriceCents, seatsLeftNext;
  final DateTime? nextDepartureAt;
  final List<String> departsFrom;
}

class Departure {
  Departure.fromJson(Json j)
      : id = j['id'] as String,
        tripId = j['tripId'] as String,
        departureProvince = j['departureProvince'] as String,
        departureArea = j['departureArea'] as String,
        meetingPlace = j['meetingPlace'] as String,
        departureAt = DateTime.parse(j['departureAt'] as String),
        returnDate = j['returnDate'] as String,
        capacity = asInt(j['capacity']),
        seatsBooked = asInt(j['seatsBooked']),
        seatsLeft = asInt(j['seatsLeft']),
        adultPriceCents = asInt(j['adultPriceCents']),
        childPriceCents = asInt(j['childPriceCents']),
        bookingDeadline = DateTime.parse(j['bookingDeadline'] as String),
        bookingOpen = j['bookingOpen'] == true,
        allowInstalments = j['allowInstalments'] == true,
        depositCents = asInt(j['depositCents']),
        finalPaymentDue = j['finalPaymentDue'] as String?,
        isCancellable = j['isCancellable'] == true,
        cancellationDeadline = asDate(j['cancellationDeadline']),
        refundType = j['refundType'] as String,
        refundPercent = asIntOrNull(j['refundPercent']),
        depositRefundable = j['depositRefundable'] == true,
        cancellationNotes = j['cancellationNotes'] as String?,
        policyText = j['policyText'] as String,
        policyBadge = j['policyBadge'] as String,
        isCancelledByCompany = j['isCancelledByCompany'] == true;

  final String id, tripId, departureProvince, departureArea, meetingPlace, returnDate, refundType, policyText, policyBadge;
  final DateTime departureAt, bookingDeadline;
  final int capacity, seatsBooked, seatsLeft, adultPriceCents, childPriceCents, depositCents;
  final bool bookingOpen, allowInstalments, isCancellable, depositRefundable, isCancelledByCompany;
  final String? finalPaymentDue, cancellationNotes;
  final DateTime? cancellationDeadline;
  final int? refundPercent;

  String get departsFrom => '$departureArea, $departureProvince';

  /// Updated seat count from a Supabase Realtime row (snake_case columns).
  Departure withSeatsBooked(int booked) {
    final j = toJsonForCopy()..['seatsBooked'] = booked;
    j['seatsLeft'] = (capacity - booked).clamp(0, capacity);
    j['bookingOpen'] = bookingOpen && capacity - booked > 0;
    return Departure.fromJson(j);
  }

  Json toJsonForCopy() => {
        'id': id,
        'tripId': tripId,
        'departureProvince': departureProvince,
        'departureArea': departureArea,
        'meetingPlace': meetingPlace,
        'departureAt': departureAt.toIso8601String(),
        'returnDate': returnDate,
        'capacity': capacity,
        'seatsBooked': seatsBooked,
        'seatsLeft': seatsLeft,
        'adultPriceCents': adultPriceCents,
        'childPriceCents': childPriceCents,
        'bookingDeadline': bookingDeadline.toIso8601String(),
        'bookingOpen': bookingOpen,
        'allowInstalments': allowInstalments,
        'depositCents': depositCents,
        'finalPaymentDue': finalPaymentDue,
        'isCancellable': isCancellable,
        'cancellationDeadline': cancellationDeadline?.toIso8601String(),
        'refundType': refundType,
        'refundPercent': refundPercent,
        'depositRefundable': depositRefundable,
        'cancellationNotes': cancellationNotes,
        'policyText': policyText,
        'policyBadge': policyBadge,
        'isCancelledByCompany': isCancelledByCompany,
      };
}

class TripImage {
  TripImage.fromJson(Json j)
      : id = j['id'] as String,
        url = j['url'] as String,
        thumbnailUrl = j['thumbnailUrl'] as String?,
        sortOrder = asInt(j['sortOrder']);
  final String id, url;
  final String? thumbnailUrl;
  final int sortOrder;
}

class ItineraryDay {
  ItineraryDay(this.dayNumber, this.title, this.description);
  ItineraryDay.fromJson(Json j)
      : dayNumber = asInt(j['dayNumber']),
        title = j['title'] as String,
        description = (j['description'] ?? '') as String;
  final int dayNumber;
  final String title, description;
  Json toJson() => {'dayNumber': dayNumber, 'title': title, 'description': description};
}

class SpecialBadge {
  SpecialBadge.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        type = j['type'] as String,
        percentOff = asInt(j['percentOff']),
        minTravellers = asIntOrNull(j['minTravellers']),
        description = j['description'] as String?;
  final String id, name, type;
  final int percentOff;
  final int? minTravellers;
  final String? description;
}

class TripDetail {
  TripDetail.fromJson(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        destination = j['destination'] as String,
        destinationCountry = j['destinationCountry'] as String,
        isCrossBorder = j['isCrossBorder'] == true,
        category = j['category'] as String,
        audience = j['audience'] as String,
        minGrade = asIntOrNull(j['minGrade']),
        maxGrade = asIntOrNull(j['maxGrade']),
        activities = asStrings(j['activities']),
        tagline = j['tagline'] as String?,
        description = (j['description'] ?? '') as String,
        coverImageUrl = j['coverImageUrl'] as String?,
        included = WhatsIncluded.fromJson(asJson(j['included'])),
        images = asList(j['images'], TripImage.fromJson),
        itinerary = asList(j['itinerary'], ItineraryDay.fromJson),
        departures = asList(j['departures'], Departure.fromJson),
        specials = asList(j['specials'], SpecialBadge.fromJson),
        averageRating = (j['averageRating'] as num?)?.toDouble(),
        reviewCount = asInt(j['reviewCount']),
        isPublished = j['isPublished'] == true;

  final String id, title, destination, destinationCountry, category, audience, description;
  final bool isCrossBorder, isPublished;
  final int? minGrade, maxGrade;
  final List<String> activities;
  final String? tagline, coverImageUrl;
  final WhatsIncluded included;
  final List<TripImage> images;
  final List<ItineraryDay> itinerary;
  final List<Departure> departures;
  final List<SpecialBadge> specials;
  final double? averageRating;
  final int reviewCount;

  bool get isYouthCamp => audience == 'high_school';
  bool get isAdultsOnly => audience == 'adults_only';
  List<String> get gallery => [
        if (images.isEmpty && coverImageUrl != null) coverImageUrl!,
        ...images.map((i) => i.url),
      ];
}

class Review {
  Review.fromJson(Json j)
      : id = j['id'] as String,
        rating = asInt(j['rating']),
        comment = j['comment'] as String?,
        customerFirstName = j['customerFirstName'] as String,
        createdAt = DateTime.parse(j['createdAt'] as String);
  final String id, customerFirstName;
  final int rating;
  final String? comment;
  final DateTime createdAt;
}

class Special {
  Special.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        description = j['description'] as String?,
        type = j['type'] as String,
        percentOff = asInt(j['percentOff']),
        minTravellers = asIntOrNull(j['minTravellers']),
        promoCode = j['promoCode'] as String?,
        isPublic = j['isPublic'] == true,
        maxUses = asIntOrNull(j['maxUses']),
        timesUsed = asInt(j['timesUsed']),
        startsAt = DateTime.parse(j['startsAt'] as String),
        endsAt = DateTime.parse(j['endsAt'] as String),
        isActive = j['isActive'] == true,
        bannerImageUrl = j['bannerImageUrl'] as String?,
        tripIds = asStrings(j['tripIds']);
  final String id, name, type;
  final String? description, promoCode, bannerImageUrl;
  final int percentOff, timesUsed;
  final int? minTravellers, maxUses;
  final bool isPublic, isActive;
  final DateTime startsAt, endsAt;
  final List<String> tripIds;
}

class DepartureLocation {
  DepartureLocation.fromJson(Json j)
      : province = j['province'] as String,
        areas = asStrings(j['areas']);
  final String province;
  final List<String> areas;
}

class TripFilters {
  const TripFilters({this.search, this.category, this.province, this.area, this.maxPriceCents, this.from, this.to});
  final String? search, category, province, area;
  final int? maxPriceCents;
  final DateTime? from, to;

  bool get isEmpty =>
      (search ?? '').isEmpty && category == null && province == null && area == null && maxPriceCents == null && from == null && to == null;

  Map<String, dynamic> toQuery() => {
        'search': search,
        'category': category,
        'departureProvince': province,
        'departureArea': area,
        'maxPriceCents': maxPriceCents,
        'from': from == null ? null : '${from!.year.toString().padLeft(4, '0')}-${from!.month.toString().padLeft(2, '0')}-${from!.day.toString().padLeft(2, '0')}',
        'to': to == null ? null : '${to!.year.toString().padLeft(4, '0')}-${to!.month.toString().padLeft(2, '0')}-${to!.day.toString().padLeft(2, '0')}',
        'pageSize': 50,
      };

  @override
  bool operator ==(Object other) =>
      other is TripFilters &&
      other.search == search &&
      other.category == category &&
      other.province == province &&
      other.area == area &&
      other.maxPriceCents == maxPriceCents &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(search, category, province, area, maxPriceCents, from, to);
}
