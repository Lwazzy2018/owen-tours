import '../../core/api/api_client.dart';
import '../trips/models.dart';

class PlannedInstalment {
  PlannedInstalment.fromJson(Json j)
      : sequence = asInt(j['sequence']),
        dueDate = j['dueDate'] as String,
        amountCents = asInt(j['amountCents']);
  final int sequence, amountCents;
  final String dueDate;
}

class PricePreview {
  PricePreview.fromJson(Json j)
      : adults = asInt(j['adults']),
        children = asInt(j['children']),
        adultPriceCents = asInt(j['adultPriceCents']),
        childPriceCents = asInt(j['childPriceCents']),
        subtotalCents = asInt(j['subtotalCents']),
        discountName = j['discountName'] as String?,
        discountPercent = asIntOrNull(j['discountPercent']),
        discountCents = asInt(j['discountCents']),
        discountPendingVerification = j['discountPendingVerification'] == true,
        totalCents = asInt(j['totalCents']),
        depositCents = asInt(j['depositCents']),
        balanceAfterDepositCents = asInt(j['balanceAfterDepositCents']),
        instalmentsAvailable = j['instalmentsAvailable'] == true,
        instalmentPlan = asList(j['instalmentPlan'], PlannedInstalment.fromJson),
        promoCodeError = j['promoCodeError'] as String?,
        policyText = j['policyText'] as String,
        seatsLeft = asInt(j['seatsLeft']);
  final int adults, children, adultPriceCents, childPriceCents, subtotalCents, discountCents, totalCents, depositCents;
  final int balanceAfterDepositCents, seatsLeft;
  final String? discountName, promoCodeError;
  final int? discountPercent;
  final bool discountPendingVerification, instalmentsAvailable;
  final List<PlannedInstalment> instalmentPlan;
  final String policyText;
}

class BookingSummary {
  BookingSummary.fromJson(Json j)
      : id = j['id'] as String,
        reference = j['reference'] as String,
        status = j['status'] as String,
        tripTitle = j['tripTitle'] as String,
        tripId = j['tripId'] as String,
        coverImageUrl = j['coverImageUrl'] as String?,
        departureAt = DateTime.parse(j['departureAt'] as String),
        departsFrom = j['departsFrom'] as String,
        travellers = asInt(j['travellers']),
        totalCents = asInt(j['totalCents']),
        amountPaidCents = asInt(j['amountPaidCents']),
        nextDueDate = j['nextDueDate'] as String?,
        nextDueCents = asIntOrNull(j['nextDueCents']),
        customerName = (j['customerName'] ?? '') as String,
        createdAt = DateTime.parse(j['createdAt'] as String),
        refundStatus = (j['refundStatus'] ?? 'none') as String;
  final String id, reference, status, tripTitle, tripId, departsFrom, customerName, refundStatus;
  final String? coverImageUrl, nextDueDate;
  final DateTime departureAt, createdAt;
  final int travellers, totalCents, amountPaidCents;
  final int? nextDueCents;
  bool get isUpcoming => departureAt.isAfter(DateTime.now()) && status != 'cancelled' && status != 'expired';
}

class Traveller {
  Traveller.fromJson(Json j)
      : id = j['id'] as String,
        fullName = j['fullName'] as String,
        idNumberMasked = j['idNumberMasked'] as String?,
        passportNumberMasked = j['passportNumberMasked'] as String?,
        passportExpiry = j['passportExpiry'] as String?,
        phone = j['phone'] as String?,
        isChild = j['isChild'] == true,
        dateOfBirth = j['dateOfBirth'] as String?,
        schoolGrade = asIntOrNull(j['schoolGrade']),
        medicalNotes = j['medicalNotes'] as String?,
        allergies = j['allergies'] as String?;
  final String id, fullName;
  final String? idNumberMasked, passportNumberMasked, passportExpiry, phone, dateOfBirth, medicalNotes, allergies;
  final bool isChild;
  final int? schoolGrade;
}

class Guardian {
  Guardian.fromJson(Json j)
      : guardianName = j['guardianName'] as String,
        guardianPhone = j['guardianPhone'] as String,
        guardianRelationship = j['guardianRelationship'] as String,
        emergencyContactName = j['emergencyContactName'] as String,
        emergencyContactPhone = j['emergencyContactPhone'] as String;
  final String guardianName, guardianPhone, guardianRelationship, emergencyContactName, emergencyContactPhone;
}

class Instalment {
  Instalment.fromJson(Json j)
      : id = j['id'] as String,
        sequence = asInt(j['sequence']),
        dueDate = j['dueDate'] as String,
        amountCents = asInt(j['amountCents']),
        status = j['status'] as String,
        paidAt = asDate(j['paidAt']);
  final String id, dueDate, status;
  final int sequence, amountCents;
  final DateTime? paidAt;
}

class PaymentRecord {
  PaymentRecord.fromJson(Json j)
      : id = j['id'] as String,
        purpose = j['purpose'] as String,
        amountCents = asInt(j['amountCents']),
        status = j['status'] as String,
        createdAt = DateTime.parse(j['createdAt'] as String),
        paidAt = asDate(j['paidAt']);
  final String id, purpose, status;
  final int amountCents;
  final DateTime createdAt;
  final DateTime? paidAt;
}

class BookingDiscount {
  BookingDiscount.fromJson(Json j)
      : id = j['id'] as String,
        name = j['name'] as String,
        percentOff = asInt(j['percentOff']),
        discountCents = asInt(j['discountCents']),
        status = j['status'] as String,
        reviewNote = j['reviewNote'] as String?,
        hasStudentId = j['hasStudentId'] == true;
  final String id, name, status;
  final int percentOff, discountCents;
  final String? reviewNote;
  final bool hasStudentId;
}

class Booking {
  Booking.fromJson(Json j)
      : id = j['id'] as String,
        reference = j['reference'] as String,
        status = j['status'] as String,
        paymentPlan = j['paymentPlan'] as String,
        tripId = j['tripId'] as String,
        tripTitle = j['tripTitle'] as String,
        coverImageUrl = j['coverImageUrl'] as String?,
        isCrossBorder = j['isCrossBorder'] == true,
        audience = j['audience'] as String,
        included = WhatsIncluded.fromJson(asJson(j['included'])),
        departure = Departure.fromJson(asJson(j['departure'])),
        adults = asInt(j['adults']),
        children = asInt(j['children']),
        subtotalCents = asInt(j['subtotalCents']),
        discountCents = asInt(j['discountCents']),
        totalCents = asInt(j['totalCents']),
        depositCents = asInt(j['depositCents']),
        amountPaidCents = asInt(j['amountPaidCents']),
        balanceCents = asInt(j['balanceCents']),
        expiresAt = asDate(j['expiresAt']),
        policyText = j['policyText'] as String,
        canCancel = j['canCancel'] == true,
        cannotCancelReason = j['cannotCancelReason'] as String?,
        cancellationDeadline = asDate(j['cancellationDeadline']),
        cancelledAt = asDate(j['cancelledAt']),
        cancellationReason = j['cancellationReason'] as String?,
        refundCents = asInt(j['refundCents']),
        refundStatus = j['refundStatus'] as String,
        travellers = asList(j['travellers'], Traveller.fromJson),
        guardian = j['guardian'] == null ? null : Guardian.fromJson(asJson(j['guardian'])),
        discount = j['discount'] == null ? null : BookingDiscount.fromJson(asJson(j['discount'])),
        instalments = asList(j['instalments'], Instalment.fromJson),
        payments = asList(j['payments'], PaymentRecord.fromJson),
        customerName = (j['customerName'] ?? '') as String,
        customerPhone = j['customerPhone'] as String?,
        canReview = j['canReview'] == true,
        createdAt = DateTime.parse(j['createdAt'] as String);

  final String id, reference, status, paymentPlan, tripId, tripTitle, audience, policyText, refundStatus, customerName;
  final String? coverImageUrl, cannotCancelReason, cancellationReason, customerPhone;
  final bool isCrossBorder, canCancel, canReview;
  final WhatsIncluded included;
  final Departure departure;
  final int adults, children, subtotalCents, discountCents, totalCents, depositCents, amountPaidCents, balanceCents, refundCents;
  final DateTime? expiresAt, cancellationDeadline, cancelledAt;
  final DateTime createdAt;
  final List<Traveller> travellers;
  final Guardian? guardian;
  final BookingDiscount? discount;
  final List<Instalment> instalments;
  final List<PaymentRecord> payments;

  bool get isActive => status == 'pending' || status == 'confirmed' || status == 'paid';
  bool get needsDeposit => paymentPlan == 'instalments' && amountPaidCents < depositCents;
  Instalment? get nextInstalment {
    final unpaid = instalments.where((i) => i.status == 'due' || i.status == 'overdue').toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return unpaid.isEmpty ? null : unpaid.first;
  }

  double get paidFraction => totalCents == 0 ? 1 : (amountPaidCents / totalCents).clamp(0, 1).toDouble();
}

class CancelPreview {
  CancelPreview.fromJson(Json j)
      : allowed = j['allowed'] == true,
        reason = j['reason'] as String?,
        deadline = asDate(j['deadline']),
        amountPaidCents = asInt(j['amountPaidCents']),
        refundCents = asInt(j['refundCents']),
        policyText = j['policyText'] as String;
  final bool allowed;
  final String? reason;
  final DateTime? deadline;
  final int amountPaidCents, refundCents;
  final String policyText;
}

class PaymentRedirect {
  PaymentRedirect.fromJson(Json j)
      : paymentId = j['paymentId'] as String,
        amountCents = asInt(j['amountCents']),
        url = j['url'] as String,
        checkoutUrl = j['checkoutUrl'] as String?;
  final String paymentId, url;
  final String? checkoutUrl;
  final int amountCents;
}

/// Editable traveller in the booking form.
class TravellerDraft {
  String fullName = '';
  String idNumber = '';
  String passportNumber = '';
  DateTime? passportExpiry;
  String phone = '';
  bool isChild = false;
  DateTime? dateOfBirth;
  int? schoolGrade;
  String medicalNotes = '';
  String allergies = '';

  Json toJson() => {
        'fullName': fullName.trim(),
        'idNumber': _n(idNumber),
        'passportNumber': _n(passportNumber),
        'passportExpiry': passportExpiry == null ? null : _date(passportExpiry!),
        'phone': _n(phone),
        'isChild': isChild,
        'dateOfBirth': dateOfBirth == null ? null : _date(dateOfBirth!),
        'schoolGrade': schoolGrade,
        'medicalNotes': _n(medicalNotes),
        'allergies': _n(allergies),
      };

  static String? _n(String v) => v.trim().isEmpty ? null : v.trim();
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
