import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';

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
  double price;
  int stock;

  Product({
    required this.id,
    required this.name,
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
}

// Model Transaksi
class TransactionRecord {
  String id;
  DateTime date;
  List<CartItem> items;
  double total;
  double payAmount;
  double change;

  TransactionRecord({
    required this.id,
    required this.date,
    required this.items,
    required this.total,
    required this.payAmount,
    required this.change,
  });
}

// Master Tampilan Utama
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  // Database Sementara / Default (akan ditimpa jika Google Sheets tersambung)
  List<Product> products = [
    Product(id: '1', name: 'Beras C4 (1 kg)', price: 14000, stock: 50),
    Product(id: '2', name: 'Minyak Goreng 1L', price: 16500, stock: 24),
    Product(id: '3', name: 'Gula Pasir 1 kg', price: 17500, stock: 30),
    Product(id: '4', name: 'Telur Ayam 1 kg', price: 28000, stock: 15),
    Product(id: '5', name: 'Mie Goreng', price: 3000, stock: 100),
  ];

  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];

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

  // Fungsi Ambil Data dari Google Sheets
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
                      id: item['id'],
                      name: item['name'],
                      price: (item['price'] as num).toDouble(),
                      stock: (item['stock'] as num).toInt(),
                    ))
                .toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat dari Google Sheets: $e");
    }
  }

  // Fungsi Kirim Produk Baru ke Google Sheets
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
            Text(
              'Warung Barokah',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Kiarajangkung',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
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
            icon: Icon(Icons.shopping_cart),
            label: 'Kasir',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'Produk/Stok',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Riwayat',
          ),
        ],
      ),
    );
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double totalBelanja = cart.fold(0, (sum, item) => sum + item.totalPrice);

    return Column(
      children: [
        Expanded(
          flex: 2,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final prod = products[index];
              return ListTile(
                title: Text(prod.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${currencyFormatter.format(prod.price)} | Stok: ${prod.stock}'),
                trailing: ElevatedButton(
                  onPressed: prod.stock > 0
                      ? () {
                          setState(() {
                            int existingIndex =
                                cart.indexWhere((c) => c.product.id == prod.id);
                            if (existingIndex != -1) {
                              if (cart[existingIndex].quantity < prod.stock) {
                                cart[existingIndex].quantity++;
                              }
                            } else {
                              cart.add(CartItem(product: prod, quantity: 1));
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
                            '${item.quantity} x ${currencyFormatter.format(item.product.price)} = ${currencyFormatter.format(item.totalPrice)}'),
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
                  const Text('Total Belanja:', style: TextStyle(fontSize: 12)),
                  Text(
                    currencyFormatter.format(totalBelanja),
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
                    cart.isEmpty ? null : () => showPaymentDialog(totalBelanja),
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

  // Dialog Pembayaran
  void showPaymentDialog(double total) {
    TextEditingController payController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pembayaran'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total: ${currencyFormatter.format(total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              TextField(
                controller: payController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Uang Diterima',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                double bayar = double.tryParse(payController.text) ?? 0;
                if (bayar >= total) {
                  double kembalian = bayar - total;

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
                    total: total,
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
  }

  // Fungsi Cetak Bluetooth menggunakan flutter_bluetooth_printer
  Future<void> printReceiptViaBluetooth(TransactionRecord trx) async {
    try {
      final device = await SelectPrinter.connect(context);
      if (device != null) {
        await FlutterBluetoothPrinter.print(
          address: device.address,
          builder: (context) {
            return Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('WARUNG BAROKAH KIARAJANGKUNG',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Text('Kiarajangkung, Sukahening, Tasikmalaya',
                      style: TextStyle(fontSize: 10)),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'No: #${trx.id} | ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}',
                        style: const TextStyle(fontSize: 10)),
                  ),
                  const Divider(),
                  ...trx.items.map((item) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text('${item.product.name} x${item.quantity}',
                                  style: const TextStyle(fontSize: 12))),
                          Text(currencyFormatter.format(item.totalPrice),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      )),
                  const Divider(),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kembali:'),
                      Text(currencyFormatter.format(trx.change)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Terima Kasih Atas Kunjungan Anda!',
                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ),
            );
          },
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak: $e')),
      );
    }
  }

  // Struk / Cetak Preview
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Text('Kiarajangkung, Sukahening, Tasikmalaya',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
                const Divider(),
                Text(
                    'No: #${trx.id} | ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}',
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kembali:'),
                    Text(currencyFormatter.format(trx.change)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Terima Kasih Atas Kunjungan Anda!',
                    style:
                        TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                printReceiptViaBluetooth(trx);
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Cetak Bluetooth'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            )
          ],
        );
      },
    );
  }

  // ================= 2. HALAMAN MANAJEMEN PRODUK =================
  Widget buildProductManagementPage() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green[700],
        onPressed: () => showAddProductDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final prod = products[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: ListTile(
              title: Text(prod.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                  'Harga: ${currencyFormatter.format(prod.price)} | Stok: ${prod.stock} Pcs'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => showEditProductDialog(prod),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        products.removeAt(index);
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void showAddProductDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController priceCtrl = TextEditingController();
    TextEditingController stockCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Produk Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Barang')),
            TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga (Rp)')),
            TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stok Awal')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                Product newProd = Product(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text,
                  price: double.tryParse(priceCtrl.text) ?? 0,
                  stock: int.tryParse(stockCtrl.text) ?? 0,
                );
                setState(() {
                  products.add(newProd);
                });
                addProductToGoogleSheets(newProd);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Produk berhasil ditambahkan & disimpan ke Google Sheets!')),
                );
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void showEditProductDialog(Product product) {
    TextEditingController nameCtrl = TextEditingController(text: product.name);
    TextEditingController priceCtrl =
        TextEditingController(text: product.price.toInt().toString());
    TextEditingController stockCtrl =
        TextEditingController(text: product.stock.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Produk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Barang')),
            TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga (Rp)')),
            TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stok')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                product.name = nameCtrl.text;
                product.price =
                    double.tryParse(priceCtrl.text) ?? product.price;
                product.stock = int.tryParse(stockCtrl.text) ?? product.stock;
              });
              Navigator.pop(context);
            },
            child: const Text('Update'),
          )
        ],
      ),
    );
  }

  // ================= 3. HALAMAN RIWAYAT & LAPORAN =================
  Widget buildHistoryPage() {
    double totalOmset = transactions.fold(0, (sum, trx) => sum + trx.total);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.green[50],
          child: Column(
            children: [
              const Text('Total Omset Harian:',
                  style: TextStyle(fontSize: 14, color: Colors.black87)),
              Text(
                currencyFormatter.format(totalOmset),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800]),
              ),
              Text('${transactions.length} Transaksi Terjadi',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: transactions.isEmpty
              ? const Center(child: Text('Belum ada transaksi hari ini'))
              : ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final trx = transactions[transactions.length - 1 - index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: ListTile(
                        title: Text('Nota #${trx.id}'),
                        subtitle: Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(trx.date)),
                        trailing: Text(
                          currencyFormatter.format(trx.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        onTap: () => showReceiptDialog(trx),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

