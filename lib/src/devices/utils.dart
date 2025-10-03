String cleanIPaddress(String addr) {
  return addr
      .replaceFirst("https://", "")
      .replaceFirst("https://", "")
      .replaceFirst("/", "");
}
