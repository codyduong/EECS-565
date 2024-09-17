use bon::builder;
use clap::Parser;
use futures::stream::{self};
use futures::StreamExt;
use std::collections::HashSet;
use std::fs::File;
use std::io::{self, BufRead};
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::{mpsc, RwLock};

#[derive(Parser, Debug)]
#[command()]
struct Args {
  encrypted: String,
  key_length: usize,
  first_word_length: usize,
  #[arg(default_value = "dict.txt")]
  dict_path: String,
}

#[tokio::main(flavor = "multi_thread", worker_threads = 16)]
async fn main() {
  let args = Args::parse();

  run_cracker()
    .encrypted(&args.encrypted)
    .key_length(args.key_length)
    .first_word_length(args.first_word_length)
    .dict_path(&args.dict_path)
    .call()
    .await
}

#[builder]
async fn run_cracker(encrypted: &str, key_length: usize, first_word_length: usize, dict_path: &str) {
  let word_set = Arc::new(load_word_set().path(dict_path).call());

  // hmm im doing something wrong
  // let (sender, mut receiver) = mpsc::channel(u16::MAX as usize);
  let (sender, mut receiver) = mpsc::channel(1); // fixed

  let results = Arc::new(RwLock::new(Vec::<(String, String)>::new()));

  let results_clone = Arc::clone(&results);
  let receiver_task = tokio::spawn(async move {
    while let Some(found_key) = receiver.recv().await {
      let mut keys = results_clone.write().await;
      keys.push(found_key);
    }
  });

  let start = Instant::now();

  let alphabet: Vec<char> = ('A'..='Z').collect();
  let permutations = generate_permutations_iter()
    .alphabet(&alphabet)
    .length(key_length)
    .call();

  println!("Completed permutations {:?}", start.elapsed());
  
  // we want to support multiple senders, but don't want to increment the sender ref count
  // until we actually need it. so arcmutex this. then lock and clone the inner sender
  // if we are using it.
  let sender = Arc::new(Mutex::new(sender));

  let task_stream = stream::iter(permutations)
    .chunks(64)
    .for_each_concurrent(None, |chunk| {
      let word_set = word_set.clone();
      let encrypted = Arc::new(encrypted.to_string());
      let sender = sender.clone();

      async move {
        let futures = chunk.into_iter().map(move |possible_key| {
          let word_set = word_set.clone();
          let encrypted = encrypted.clone();
          let sender = sender.clone();

          async move {
            let res = decrypt_vigenere_firstword()
              .key(&possible_key)
              .text(&encrypted)
              .first_word_length(first_word_length)
              .word_set(&word_set)
              .call();

            if let Some(res) = res {
              let sender = sender.lock().unwrap().clone();
              sender.send((possible_key, res)).await.unwrap();
            }
          }
        });

        let mut futures_unordered = futures::stream::FuturesUnordered::new();
        futures_unordered.extend(futures);

        while let Some(_) = futures_unordered.next().await {}
      }
    });

  task_stream.await;
  drop(sender);
  receiver_task.await.unwrap();

  println!("\nKeys:\n{:#?}", results.read().await);

  println!("Completed in {:?}", start.elapsed());
}

#[builder]
fn generate_permutations_iter(alphabet: &[char], length: usize) -> impl Iterator<Item = String> + '_ {
  (0..alphabet.len().pow(length as u32)).map(move |i| {
    let mut result = String::with_capacity(length);
    let mut idx = i;
    for _ in 0..length {
      result.push(alphabet[idx % alphabet.len()]);
      idx /= alphabet.len();
    }
    result
  })
}

#[builder]
fn load_word_set(path: &str) -> HashSet<String> {
  let file = File::open(path).expect("Error opening dictionary file");
  let reader = io::BufReader::new(file);
  reader
    .lines()
    .filter_map(|line| {
      let word = line.ok()?.to_uppercase();
      if !word.is_empty() {
        Some(word)
      } else {
        None
      }
    })
    .collect()
}

#[builder]
fn decrypt_vigenere_firstword(
  key: &str,
  text: &str,
  first_word_length: usize,
  word_set: &HashSet<String>,
) -> Option<String> {
  let decrypted = decrypt_vigenere().key(key).text(text).call();
  let first_word: String = decrypted.chars().take(first_word_length).collect();
  if word_set.contains(&first_word) {
    Some(decrypted)
  } else {
    None
  }
}

#[builder]
fn decrypt_vigenere(key: &str, text: &str) -> String {
  text
    .chars()
    .zip(key.chars().cycle())
    .map(|(c, k)| decrypt_char().k(k).c(c).call())
    .collect()
}

#[builder]
fn decrypt_char(k: char, c: char) -> char {
  if c.is_alphabetic() {
    let decrypted_char =
      (((c.to_ascii_uppercase() as u8 - b'A') as i32 - (k as u8 - b'A') as i32 + 26) % 26) as u8 + b'A';
    decrypted_char as char
  } else {
    c
  }
}
