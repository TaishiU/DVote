/*
【投票】
次のコントラクトは非常に複雑ですが、Solidityの多くの機能を紹介しています。 投票を実施します。 
もちろん、電子投票の主な問題は、正しい人に投票権を割り当てる方法と、操作を防ぐ方法です。 
ここではすべての問題を解決するわけではありませんが、少なくとも、開票が自動的かつ完全に透過的に
なるように、委任された投票を行う方法を示します。
アイデアは、投票ごとに1つのコントラクトを作成し、各オプションに短い名前を付けることです。 
次に、議長を務めるコントラクトの作成者は、各アドレスに個別に投票する権利を与えます。
アドレスの背後にいる人は、自分で投票するか、信頼できる人に投票を委任するかを選択できます。
投票時間の終わりに、winningProposal（）は投票数が最も多い候補者を返します。
*/



pragma solidity ^0.5.16;

/// @title 委任による投票
contract DVote {

    address public chairperson; //議長のアドレス

    // 候補者の構造体
    struct Proposal {
        bytes32 name;   // 名前（最大32バイト）
        uint voteCount; // 累積投票数
    }

    // `Proposal`構造体の可変長配列(動的なサイズの配列),対は固定長配列(配列の長さが固定)
    Proposal[] public proposals;


    // 投票者(一般人)の構造体
    struct Voter {
        uint weight; // 重みは委任によって累積されます
        bool voted;  // trueの場合、その人はすでに投票しています
        address delegate; // 委任された人
        uint vote;   // 投票された候補者のインデックス
    }

    //可能なアドレスごとに `Voter`構造体を格納する状態変数を宣言する
    mapping(address => Voter) public voters;


    //⭐️配列と連想配列(mapping)の違い
    // 配列は、①数字②添え字が0から始まる③要素が増えるごとに数字が1増える
    // 連想配列(mapping)は、①keyとvalueのセット②添え字を自由に設定できる → 添え字が「0,1,2...」ではなく「address」でも良い


    /// 新しい投票用紙を作成して `proposalNames`の1つを選択します。
    /// コンストラクター(初期設定)
    constructor(bytes32[] proposalNames) public {
        chairperson = msg.sender; //msg.senderのアドレスが議長となる
        voters[chairperson].weight = 1;

        //提供された候補者名ごとに、新しい候補者オブジェクトを作成し、配列の最後に追加します。
        for (uint i = 0; i < proposalNames.length; i++) {
            // `Proposal（{...}）`は一時的なものを作成します
            // 候補者オブジェクトと `proposals.push（...）`
            // `proposals`の最後に追加します。
            proposals.push(Proposal({
                name: proposalNames[i],
                voteCount: 0
            }));
        }
    }

    // `voter`に投票する権利を与える
    // 議長のみが呼び出すことができる
    function giveRightToVote(address voter) public {
        // `require`の最初の引数が` false`と評価された場合、実行は終了し、
        // StateとEtherバランスへのすべての変更が元に戻されます。
        // これは、古いEVMバージョンではすべてのガスを消費していましたが、現在は消費していません。
        // 関数が正しく呼び出されているかどうかを確認するには、 `require`を使用することをお勧めします。
        // 2番目の引数として、何が悪かったのかについての説明を記述することもできます。
        require(
            msg.sender == chairperson, //msg.senderが議長であるか確認
            "Only chairperson can give right to vote." //msg.senderが議長でなければメッセージを表示
        );
        require(
            !voters[voter].voted, //投票者がまだ投票していないことを確認
            "The voter already voted."
        );
        require(voters[voter].weight == 0);
        voters[voter].weight = 1; //「投票済み」に変更
    }

    /// 投票を代理人 `to`に委任する
    function delegate(address to) public {
        // 参照を割り当てます
        Voter storage sender = voters[msg.sender]; //senderは投票権を代理人に送る人。storageなので、ブロックチェーンに情報が書き込まれる
        require(!sender.voted, "You already voted."); //投票者が、代理人に投票権を送る前にすでに投票していないか確認

        require(to != msg.sender, "Self-delegation is disallowed."); //代理人がmsg.senderでないことを確認

        // 代理人`to`も委任されている限り、別の人に再委任することができる
        // しかし、一般的に、このようなループは非常に危険である
        // なぜなら、ループが長すぎると、ガス代が高額になる可能性があるため
        // この場合、委任は実行されませんが、他の状況では、そのようなループによってコントラクトが完全に「スタック」する可能性がある
        while (voters[to].delegate != address(0)) {
            to = voters[to].delegate;

            // 委任にループが見つかった場合、ループを中止する
            require(to != msg.sender, "Found loop in delegation."); //代理人がmsg.senderでないことを確認。msg.senderであれば投票権がループしてしまう
        }

        // 投票権を委任した人`sender`は参照であるため、これにより` voters [msg.sender] .voted`が変更されます
        sender.voted = true; // senderの投票権は「投票済み」になる
        sender.delegate = to;
        Voter storage delegate_ = voters[to]; // delegate_ = to(代理人)
        if (delegate_.voted) {
            //代理人がすでに投票している場合は、候補者の投票数に直接追加される
            proposals[delegate_.vote].voteCount += sender.weight;
        } else {
            //代理人がまだ投票していない場合は、代理人の重みにsenderの重みを追加します。
            delegate_.weight += sender.weight;
        }
    }

    ///提案 `proposals [proposal] .name`にあなたの投票（あなたに委任された投票を含む）を与える
    function vote(uint proposal) public {
        Voter storage sender = voters[msg.sender];
        require(!sender.voted, "Already voted.");
        sender.voted = true;
        sender.vote = proposal;

        // `proposal`が配列の範囲外の場合、
        //これは自動的にスローされ、すべての変更が元に戻ります。

        proposals[proposal].voteCount += sender.weight;
    }

    /// @dev 以前のすべての投票を考慮に入れて勝者の提案を計算する
    function winningProposal() public view returns (uint winningProposal_) {
        uint winningVoteCount = 0;
        for (uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
                winningProposal_ = p;
            }
        }
    }

    // winingProposal（）関数を呼び出して、候補者の配列(Proposal[])に含まれる勝者のインデックスを取得し、勝者の名前を返す
    function winnerName() public view returns (bytes32 winnerName_) {
        winnerName_ = proposals[winningProposal()].name;
    }
}





/// Solidityでのコメントの書き方
/// @title  コントラクトのタイトル
/// @author 作成者の名前
/// @notice コントラクトの説明（どのような処理を行うかなど）
/// @dev    コントラクトの開発者向けの更なる詳細な説明
/// @author 作成者の名前
/// @notice この関数の説明
/// @param  パラメータの説明（パラメータ数分記載する）
/// @return 戻り値の説明



