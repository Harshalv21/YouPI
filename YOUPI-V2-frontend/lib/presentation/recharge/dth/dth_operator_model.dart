// Mirrors DthOperatorInfo in DthModels.kt exactly: `name` is the
// A1Topup-recognized operator string (e.g. "AIRTEL DIGITAL TV") that must
// be sent back as-is in CreateDthRechargeRequest.operator -- there is no
// separate short code, unlike what an earlier draft of this file assumed.
// `displayName` is purely for showing in the UI (e.g. "Airtel Digital TV").
class DthOperatorModel {
  final String name;         // sent to backend as `operator`
  final String displayName;  // shown in UI

  const DthOperatorModel({required this.name, required this.displayName});

  factory DthOperatorModel.fromJson(Map<String, dynamic> json) {
    return DthOperatorModel(
      name: json['name'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

// Static fallback list -- matches SUPPORTED_DTH_OPERATORS in
// DthModels.kt exactly. Used if GET /v1/recharge/dth/operators is
// slow/unavailable so the picker still renders instantly.
const List<DthOperatorModel> kFallbackDthOperators = [
  DthOperatorModel(name: 'AIRTEL DIGITAL TV', displayName: 'Airtel Digital TV'),
  DthOperatorModel(name: 'SUN DIRECT', displayName: 'Sun Direct'),
  DthOperatorModel(name: 'TATA PLAY', displayName: 'Tata Play (Tata Sky)'),
  DthOperatorModel(name: 'VIDEOCON D2H', displayName: 'Videocon d2h'),
  DthOperatorModel(name: 'DISH TV', displayName: 'Dish TV'),
];