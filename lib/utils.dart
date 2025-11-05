import 'dart:io';

// Future<String> resolveDestination(String address) async {
//   try {
//     final res = await DNSolve().lookup(address);

//     if (res.answer?.records != null) {
//       for (final record in res.answer!.records!) {
//         print(record.toBind);
//       }
//     } else {
//       final reverseRes = await DNSolve().reverseLookup(address);

//       for (final record in reverseRes) {
//         print(record.toBind);
//       }
//     }
//   } catch (e) {
//     print("error - ${e.toString()}");
//   }

//   return "";
// }

/// Attempts to resolve a given domain or IP address.
///
/// It strips common URL prefixes (like 'http://', 'https://'), performs a DNS
/// lookup, and returns the cleaned address if successful.
///
/// Throws a [SocketException] if the address cannot be resolved.
Future<String> resolveDestination(
  String sanitizedAddress, {
  int port = 80,
  Duration timeout = const Duration(seconds: 5),
  bool checkConnection = false,
}) async {
  if (sanitizedAddress.isEmpty) {
    throw const SocketException('Invalid or empty address provided.');
  }

  // 2. Resolve (DNS Lookup)
  InternetAddress hostAddress;

  try {
    // Check if it's already a valid IP address
    InternetAddress? ip = InternetAddress.tryParse(sanitizedAddress);

    if (ip != null) {
      // If it's an IP, use it directly
      hostAddress = ip;
    } else {
      // If it's a domain name, perform DNS lookup
      List<InternetAddress> addresses = await InternetAddress.lookup(
        sanitizedAddress,
      );

      if (addresses.isEmpty) {
        throw SocketException('Could not resolve host: $sanitizedAddress');
      }
      // Use the first resolved address
      hostAddress = addresses.first;
    }
  } on SocketException {
    throw SocketException('Resolution failed for $sanitizedAddress.');
  } catch (e) {
    throw SocketException(
      'An error occurred during resolution for $sanitizedAddress: $e',
    );
  }

  // 3. Check Reachability (Socket Connection)
  if (checkConnection) {
    try {
      // Attempt to connect to the resolved address on the specified port.
      // We use timeout to prevent the function from hanging indefinitely.
      await Socket.connect(hostAddress, port, timeout: timeout);

      // Connection was successful, indicating the host is reachable.
      return sanitizedAddress;
    } on SocketException {
      // The SocketException here means the connection failed,
      // which signifies that the host is NOT reachable on that port.
      throw SocketException(
        'Host $sanitizedAddress is resolvable but NOT reachable on port $port.',
      );
    } catch (e) {
      // Catch any other connection errors
      throw SocketException(
        'An unknown error occurred during reachability check: $e',
      );
    }
  } else {
    return sanitizedAddress;
  }
}
