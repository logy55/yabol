export function parseNames(value) {
  const names = value.split(/[\n,]/).map(name => name.trim()).filter(Boolean);
  if (names.length < 2 || names.length > 20) throw new Error('참여자는 2~20명으로 입력해 주세요.');
  if (names.some(name => name.length > 20)) throw new Error('이름은 20자 이하로 입력해 주세요.');
  if (new Set(names).size !== names.length) throw new Error('같은 이름이 있어요. 참여자를 구분해 주세요.');
  return names;
}

// Winning percentage excludes recorded draws; future games are assumed decisive.
export function magicNumber(total, leader, rival) {
  if (!Number.isInteger(total) || total < 1 || total > 200) throw new Error('시즌 경기 수는 1~200경기로 입력해 주세요.');
  for (const record of [leader, rival]) {
    if ([record.wins,record.losses,record.draws].some(n => !Number.isInteger(n) || n < 0) || record.wins+record.losses+record.draws > total) throw new Error('승·패·무의 합계가 시즌 경기 수를 넘을 수 없어요.');
    if (record.draws === total) throw new Error('전 경기가 무승부인 성적은 승률을 비교할 수 없어요.');
  }
  const leaderRemaining = total-leader.wins-leader.losses-leader.draws;
  const rivalRemaining = total-rival.wins-rival.losses-rival.draws;
  const leaderDenominator = total-leader.draws, rivalDenominator = total-rival.draws;
  let greatestUnclinched = -1;
  for (let wins=0; wins<=leaderRemaining; wins++) {
    for (let losses=0; losses<=rivalRemaining; losses++) {
      if ((leader.wins+wins)*rivalDenominator <= (rival.wins+rivalRemaining-losses)*leaderDenominator) greatestUnclinched = Math.max(greatestUnclinched,wins+losses);
    }
  }
  const number = greatestUnclinched+1;
  return {number:number>leaderRemaining+rivalRemaining ? null : number, leaderRemaining, rivalRemaining};
}

export function settleExpenses(names, paid) {
  if (names.length < 2 || names.length !== paid.length || new Set(names).size !== names.length) throw new Error('참여자를 확인해 주세요.');
  if (paid.some(amount => !Number.isSafeInteger(amount) || amount < 0 || amount > 1_000_000_000_000)) throw new Error('결제 금액은 0원부터 1조 원까지, 정수로 입력해 주세요.');
  const total = paid.reduce((sum, amount) => sum + amount, 0);
  const base = Math.floor(total / names.length), remainder = total % names.length;
  const shares = names.map((_, index) => base + (index < remainder ? 1 : 0));
  const balances = paid.map((amount, index) => amount - shares[index]);
  const debtors = balances.map((value, index) => ({index, amount:-value})).filter(p => p.amount > 0);
  const creditors = balances.map((value, index) => ({index, amount:value})).filter(p => p.amount > 0);
  const transfers = [];
  let debtor = 0, creditor = 0;
  while (debtor < debtors.length && creditor < creditors.length) {
    const from = debtors[debtor], to = creditors[creditor], amount = Math.min(from.amount, to.amount);
    transfers.push({from:names[from.index], to:names[to.index], amount});
    from.amount -= amount; to.amount -= amount;
    if (!from.amount) debtor++;
    if (!to.amount) creditor++;
  }
  return {total, shares, balances, transfers, remainder};
}

export function randomIndex(size) {
  const ceiling = Math.floor(0x100000000 / size) * size;
  const buffer = new Uint32Array(1);
  do { crypto.getRandomValues(buffer); } while (buffer[0] >= ceiling);
  return buffer[0] % size;
}
export function makeLadder(count, choose = randomIndex) {
  if (!Number.isInteger(count) || count < 2 || count > 20) throw new Error('사다리 인원을 확인해 주세요.');
  return Array.from({length:Math.max(20, count * 5)}, (_, index) => ({row:index, lane:choose(count - 1)}));
}
export function traceLadder(start, bars) {
  let lane = start;
  const steps = bars.map(bar => {
    const from = lane;
    if (lane === bar.lane) lane++;
    else if (lane === bar.lane + 1) lane--;
    return {row:bar.row, from, to:lane};
  });
  return {end:lane, steps};
}
