import 'package:dnsolve/dnsolve.dart';

Future<String> resolveDestination(String address) async {
  try {
    final res = await DNSolve().lookup(address);

    if (res.answer?.records != null) {
      for (final record in res.answer!.records!) {
        print(record.toBind);
      }
    }
  } catch (e) {
    try {
      final res = await DNSolve().reverseLookup(address);

      for (final record in res) {
        print(record.toBind);
      }
    } catch (e) {
      print("error");
    }
  }

  return "";
}
