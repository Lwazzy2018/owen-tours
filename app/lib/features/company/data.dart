import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class Company {
  Company.fromJson(Json j)
      : companyName = (j['companyName'] ?? 'Owen Tours and Travel') as String,
        registeredName = j['registeredName'] as String?,
        tagline = j['tagline'] as String?,
        phone = j['phone'] as String?,
        whatsapp = j['whatsapp'] as String?,
        email = j['email'] as String?,
        address = j['address'] as String?,
        facebookUrl = j['facebookUrl'] as String?,
        instagramUrl = j['instagramUrl'] as String?,
        tiktokUrl = j['tiktokUrl'] as String?,
        aboutText = j['aboutText'] as String?,
        whatsappLink = j['whatsappLink'] as String?,
        callLink = j['callLink'] as String?;

  final String companyName;
  final String? registeredName, tagline, phone, whatsapp, email, address, facebookUrl, instagramUrl, tiktokUrl, aboutText;
  final String? whatsappLink, callLink;

  Json toJson() => {
        'companyName': companyName,
        'registeredName': registeredName,
        'tagline': tagline,
        'phone': phone,
        'whatsapp': whatsapp,
        'email': email,
        'address': address,
        'facebookUrl': facebookUrl,
        'instagramUrl': instagramUrl,
        'tiktokUrl': tiktokUrl,
        'aboutText': aboutText,
      };
}

final companyProvider = FutureProvider<Company>((ref) {
  return ref.watch(apiProvider).get('/api/company', (d) => Company.fromJson(asJson(d)));
});
