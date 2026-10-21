import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

void main() {
  runApp(const WarungBarokahApp());
}

class WarungBarokahApp extends StatelessWidget {
  const WarungBarokahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warung Barokah Kiarajangkung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

// Model Barang / Produk
class Product {
  String id;
  String name;
  double buyPrice;  // Harga Beli / Modal
  double price;     // Harga Jual
  int stock;

  Product({
    required this.id,
    required this.name,
    required this.buyPrice,
    required this.price,
    required this.stock,
  });
}

// Model Item Keranjang
class CartItem {
  Product product;
  int quantity;

  CartItem({required this.product, required this.quantity});

  double get totalPrice => product.price * quantity;
  double get totalBuyPrice => product.buyPrice * quantity;
}

// Model Transaksi
class TransactionRecord {
  String id;
  DateTime date;
  List<CartItem> items;
  double subtotal;
  double discount;
  double tax;
  double total;
  double payAmount;
  double change;

  TransactionRecord({
    required this.id,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.payAmount,
    required this.change,
  });

  // Hitung Laba Bersih Transaksi ini
  double get totalCapital => items.fold(0, (sum, item) => sum + item.totalBuyPrice);
  double get netProfit => (subtotal - discount) - totalCapital;
}

// Master Tampilan Utama
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  List<Product> products = [
    Product(id: '1', name: 'Beras C4 (1 kg)', buyPrice: 12500, price: 14000, stock: 50),
    Product(id: '2', name: 'Minyak Goreng 1L', buyPrice: 14500, price: 16500, stock: 24),
    Product(id: '3', name: 'Gula Pasir 1 kg', buyPrice: 15500, price: 17500, stock: 30),
    Product(id: '4', name: 'Telur Ayam 1 kg', buyPrice: 25000, price: 28000, stock: 15),
    Product(id: '5', name: 'Mie Goreng', buyPrice: 2500, price: 3000, stock: 100),
  ];

  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];

  TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';

  TextEditingController searchMasterController = TextEditingController();
  String searchMasterQuery = '';

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    fetchProductsFromGoogleSheets();
  }

  Future<void> fetchProductsFromGoogleSheets() async {
    final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            products = data
                .map((item) => Product(
                      id: item['id'].toString(),
                      name: item['name'] ?? '',
                      buyPrice: (item['buyPrice'] as num?)?.toDouble() ?? 0,
                      price: (item['price'] as num?)?.toDouble() ?? 0,
                      stock: (item['stock'] as num?)?.toInt() ?? 0,
                    ))
                .toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat dari Google Sheets: $e");
    }
  }

  Future<void> addProductToGoogleSheets(Product newProduct) async {
    final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec');
    try {
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": newProduct.id,
          "name": newProduct.name,
          "buyPrice": newProduct.buyPrice,
          "price": newProduct.price,
          "stock": newProduct.stock,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan ke Google Sheets: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildKasirPage(),
      buildProductManagementPage(),
      buildHistoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Warung Barokah',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Kiarajangkung',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Produk',
            onPressed: () {
              fetchProductsFromGoogleSheets();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memperbarui data produk...')),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.green[700],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: 'Kasir'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2), label: 'Produk/Stok'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
        ],
      ),
    );
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);

    List<Product> filteredProducts = products.where((prod) {
      return prod.name.toLowerCase().contains(searchKasirQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search Bar Kasir
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchKasirController,
            decoration: InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchKasirQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          searchKasirController.clear();
                          searchKasirQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            onChanged: (value) {
              setState(() {
                searchKasirQuery = value;
              });
            },
          ),
        ),
        Expanded(
          flex: 2,
          child: filteredProducts.isEmpty
              ? const Center(child: Text('Produk tidak ditemukan'))
              : ListView.builder(
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final prod = filteredProducts[index];
                    return ListTile(
                      title: Text(prod.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Jual: ${currencyFormatter.format(prod.price)} \vert{} Stok:${prod.stock}'),
                      trailing: ElevatedButton(
                        onPressed: prod.stock > 0
                            ? () {
                                setState(() {
                                  int existingIndex = cart.indexWhere(
                                      (c) => c.product.id == prod.id);
                                  if (existingIndex != -1) {
                                    if (cart[existingIndex].quantity <
                                        prod.stock) {
                                      cart[existingIndex].quantity++;
                                    }
                                  } else {
                                    cart.add(
                                        CartItem(product: prod, quantity: 1));
                                  }
                                });
                              }
                            : null,
                        child: const Text('Tambah'),
                      ),
                    );
                  },
                ),
        ),
        const Divider(thickness: 2),
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[100],
            child: cart.isEmpty
                ? const Center(child: Text('Keranjang Masih Kosong'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return ListTile(
                        title: Text(item.product.name),
                        subtitle: Text(
                            '${item.quantity} x ${currencyFormatter.format(item.product.price)} =${currencyFormatter.format(item.totalPrice)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity > 1) {
                                    item.quantity--;
                                  } else {
                                    cart.removeAt(index);
                                  }
                                });
                              },
                            ),
                            Text('${item.quantity}',
                                style: const TextStyle(fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle,
                                  color: Colors.green),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity < item.product.stock) {
                                    item.quantity++;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subtotal Belanja:', style: TextStyle(fontSize: 12)),
                  Text(
                    currencyFormatter.format(subtotal),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                onPressed:
                    cart.isEmpty ? null : () => showPaymentDialog(subtotal),
                child: const Text('BAYAR',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        )
      ],
    );
  }

  void showPaymentDialog(double subtotal) {
    TextEditingController discountCtrl = TextEditingController(text: '0');
    TextEditingController taxPercentCtrl = TextEditingController(text: '0');
    TextEditingController payCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double discount = double.tryParse(discountCtrl.text) ?? 0;
            double taxPercent = double.tryParse(taxPercentCtrl.text) ?? 0;
            double taxAmount = (subtotal - discount) * (taxPercent / 100);
            double grandTotal = (subtotal - discount) + taxAmount;

            return AlertDialog(
              title: const Text('Pembayaran & Potongan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:'),
                        Text(currencyFormatter.format(subtotal),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Diskon / Potongan (Rp)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: taxPercentCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PPN (%)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('PPN Nominal:'),
                        Text(currencyFormatter.format(taxAmount)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL BAYAR:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          currencyFormatter.format(grandTotal),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green[800]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: payCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Uang Diterima',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    double bayar = double.tryParse(payCtrl.text) ?? 0;
                    if (bayar >= grandTotal) {
                      double kembalian = bayar - grandTotal;

                      for (var item in cart) {
                        item.product.stock -= item.quantity;
                      }

                      TransactionRecord trx = TransactionRecord(
                        id: DateTime.now()
                            .millisecondsSinceEpoch
                            .toString()
                            .substring(7),
                        date: DateTime.now(),
                        items: List.from(cart),
                        subtotal: subtotal,
                        discount: discount,
                        tax: taxAmount,
                        total: grandTotal,
                        payAmount: bayar,
                        change: kembalian,
                      );

                      transactions.add(trx);
                      setState(() {
                        cart.clear();
                      });

                      Navigator.pop(context);
                      showReceiptDialog(trx);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Uang pembayaran tidak cukup!')),
                      );
                    }
                  },
                  child: const Text('Proses & Struk'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Fungsi Cetak Bluetooth dengan print_bluetooth_thermal
  Future<void> printReceiptViaBluetooth(TransactionRecord trx) async {
    try {
      List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tidak ada perangkat Bluetooth tersanding!')),
        );
        return;
      }

      String macAddress = devices.first.macAdress;
      bool status =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

      if (status) {
        String receiptText = "       WARUNG BAROKAH\n"
            "       KIARAJANGKUNG\n"
            "Sukahening, Tasikmalaya\n"
            "--------------------------------\n"
            "No : #${trx.id}\n"
            "Tgl: ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}\n"
            "--------------------------------\n";

        for (var item in trx.items) {
          receiptText += "${item.product.name}\n"
              "  ${item.quantity} x ${currencyFormatter.format(item.product.price)} =${currencyFormatter.format(item.totalPrice)}\n";
        }

        receiptText += "--------------------------------\n"
            "Subtotal: ${currencyFormatter.format(trx.subtotal)}\n";
        if (trx.discount > 0) {
          receiptText +=
              "Diskon  : -${currencyFormatter.format(trx.discount)}\n";
        }
        if (trx.tax > 0) {
          receiptText += "PPN     : +${currencyFormatter.format(trx.tax)}\n";
        }
        receiptText += "Total   : ${currencyFormatter.format(trx.total)}\n"
            "Bayar   : ${currencyFormatter.format(trx.payAmount)}\n"
            "Kembali : ${currencyFormatter.format(trx.change)}\n"
            "--------------------------------\n"
            " Terimakasih Atas Kunjungan Anda\n\n\n";

        await PrintBluetoothThermal.writeString(
            printText: PrintTextSize(size: 1, text: receiptText));
        await PrintBluetoothThermal.disconnect;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Struk berhasil dicetak!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Gagal terhubung ke printer Bluetooth!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cetak: $e')),
      );
    }
  }

  void showReceiptDialog(TransactionRecord trx) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('WARUNG BAROKAH KIARAJANGKUNG',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Text('Kiarajangkung, Sukahening, Tasikmalaya',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10)),
                const Divider(),
                Text(
                    'No: #${trx.id} \vert{}${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}',
                    style: const TextStyle(fontSize: 10)),
                const Divider(),
                ...trx.items.map((item) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${item.product.name} x${item.quantity}',
                            style: const TextStyle(fontSize: 12)),
                        Text(currencyFormatter.format(item.totalPrice),
                            style: const TextStyle(fontSize: 12)),
                      ],
                    )),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:'),
                    Text(currencyFormatter.format(trx.subtotal)),
                  ],
                ),
                if (trx.discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Diskon:'),
                      Text('-${currencyFormatter.format(trx.discount)}',
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                if (trx.tax > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('PPN:'),
                      Text('+${currencyFormatter.format(trx.tax)}'),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(currencyFormatter.format(trx.total),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bayar:'),
                    Text(currencyFormatter.format(trx.payAmount)),
                  ],
                ),
                Row(
